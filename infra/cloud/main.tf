locals {
  base_domain = trimsuffix(trimspace(var.domain), ".")

  hostnames = {
    admin   = "admin.${local.base_domain}"
    chat    = "chat.${local.base_domain}"
    matrix  = "matrix.${local.base_domain}"
    account = "account.${local.base_domain}"
    rtc     = "rtc.${local.base_domain}"
  }

  managed_certificate_name = "ess-managed-cert"
  static_ip_name           = "ess-ingress-ip"
  dns_project              = trimspace(var.dns_project_id) != "" ? trimspace(var.dns_project_id) : var.project_id
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "current" {}

provider "google" {
  alias   = "dns"
  project = local.dns_project
}

resource "google_project_service" "compute" {
  project                    = var.project_id
  service                    = "compute.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "container" {
  project                    = var.project_id
  service                    = "container.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_compute_global_address" "ingress" {
  name    = local.static_ip_name
  project = var.project_id
}

resource "google_container_cluster" "autopilot" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.region

  enable_autopilot = true

  depends_on = [
    google_project_service.compute,
    google_project_service.container
  ]
}

locals {
  cluster_endpoint = "https://${google_container_cluster.autopilot.endpoint}"
  cluster_ca       = base64decode(google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate)
}

provider "kubernetes" {
  experiments {
    manifest_resource = true
  }
  load_config_file      = false
  host                   = local.cluster_endpoint
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = local.cluster_ca
}

provider "helm" {
  kubernetes = {
    load_config_file      = false
    host                   = local.cluster_endpoint
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = local.cluster_ca
  }
}

resource "kubernetes_namespace" "ess" {
  metadata {
    name = "ess"
  }
}

resource "kubernetes_manifest" "managed_certificate" {
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = local.managed_certificate_name
      namespace = kubernetes_namespace.ess.metadata[0].name
    }
    spec = {
      domains = [
        local.hostnames.chat,
        local.hostnames.admin,
        local.hostnames.matrix,
        local.hostnames.account,
        local.hostnames.rtc,
      ]
    }
  }

  depends_on = [kubernetes_namespace.ess]
}

locals {
  ingress_annotations = {
    "networking.gke.io/managed-certificates"      = local.managed_certificate_name
    "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.ingress.name
  }

  ess_values = {
    ingress = {
      className      = "gce"
      controllerType = null
      tlsEnabled     = true
      annotations    = local.ingress_annotations
    }
    serverName = local.base_domain
    elementAdmin = {
      ingress = {
        host = local.hostnames.admin
      }
    }
    elementWeb = {
      ingress = {
        host = local.hostnames.chat
      }
    }
    matrixAuthenticationService = {
      ingress = {
        host = local.hostnames.account
      }
    }
    matrixRTC = {
      ingress = {
        host = local.hostnames.rtc
      }
    }
    synapse = {
      ingress = {
        host = local.hostnames.matrix
      }
    }
  }
}

resource "helm_release" "ess" {
  name       = "ess"
  repository = "oci://ghcr.io/element-hq/ess-helm"
  chart      = "matrix-stack"
  namespace  = kubernetes_namespace.ess.metadata[0].name

  create_namespace = false
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode(local.ess_values)
  ]

  depends_on = [
    kubernetes_manifest.managed_certificate,
    google_compute_global_address.ingress
  ]
}

data "google_dns_managed_zone" "ess" {
  provider = google.dns
  name     = var.dns_zone_name
}

resource "google_dns_record_set" "ess_hosts" {
  for_each = local.hostnames
  provider = google.dns

  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.ess.name
  project      = local.dns_project

  rrdatas = [google_compute_global_address.ingress.address]
}
