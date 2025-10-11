locals {
  ingress_annotations = {
    "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.ingress.name
    "networking.gke.io/certmap"                   = google_certificate_manager_certificate_map.ess.id
    "networking.gke.io/v1beta1.FrontendConfig"    = kubernetes_manifest.frontend_config.manifest.metadata.name
  }

  cloudsql_postgres = {
    host = google_sql_database_instance.ess.private_ip_address
    port = 5432
  }

  synapse_service_account_block = {
    create = true
    name   = local.synapse_service_account_name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.synapse.email
    }
  }

  matrix_auth_service_account_block = {
    create = true
    name   = local.mas_service_account_name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.matrix_auth.email
    }
  }

  ess_values = {
    postgres = {
      enabled = false
    }
    ingress = {
      className   = "gce"
      tlsEnabled  = false
      annotations = local.ingress_annotations
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
      postgres = {
        host     = local.cloudsql_postgres.host
        port     = local.cloudsql_postgres.port
        user     = local.matrix_auth_db_user
        database = local.matrix_auth_db_name
        sslMode  = "require"
        password = {
          secret    = kubernetes_secret.matrix_auth_db.metadata[0].name
          secretKey = "password"
        }
      }
      serviceAccount = local.matrix_auth_service_account_block
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
      postgres = {
        host     = local.cloudsql_postgres.host
        port     = local.cloudsql_postgres.port
        user     = local.synapse_db_user
        database = local.synapse_db_name
        sslMode  = "require"
        password = {
          secret    = kubernetes_secret.synapse_db.metadata[0].name
          secretKey = "password"
        }
      }
      serviceAccount = local.synapse_service_account_block
      additional = {
        "00-allow-unsafe-locale" = {
          config = <<-EOT
database:
  allow_unsafe_locale: true
EOT
        }
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
    google_certificate_manager_certificate_map_entry.ess,
    google_compute_global_address.ingress,
    kubernetes_manifest.frontend_config,
    kubernetes_secret.synapse_db,
    kubernetes_secret.matrix_auth_db
  ]
}
