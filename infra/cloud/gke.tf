resource "google_container_cluster" "autopilot" {
  name     = local.cluster_name
  project  = var.project_id
  location = local.region

  enable_autopilot = true
  deletion_protection = false
  network             = google_compute_network.primary.id
  subnetwork          = google_compute_subnetwork.primary.id

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_secondary_range_name
    services_secondary_range_name = local.services_secondary_range_name
  }

  depends_on = [
    google_project_service.compute,
    google_project_service.container
  ]
}

locals {
  cluster_endpoint            = "https://${google_container_cluster.autopilot.endpoint}"
  cluster_ca                  = base64decode(google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate)
  workload_identity_namespace = google_container_cluster.autopilot.workload_identity_config[0].workload_pool
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = local.cluster_ca
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = local.cluster_ca
  }
}
