resource "google_compute_network" "primary" {
  name                    = local.vpc_network_name
  project                 = var.project_id
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "primary" {
  name          = local.subnetwork_name
  project       = var.project_id
  region        = local.region
  network       = google_compute_network.primary.id
  ip_cidr_range = local.subnetwork_ip_cidr_range

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pods_secondary_range_name
    ip_cidr_range = local.pods_secondary_cidr_range
  }

  secondary_ip_range {
    range_name    = local.services_secondary_range_name
    ip_cidr_range = local.services_secondary_cidr_range
  }
}

resource "google_compute_address" "ingress" {
  name    = local.static_ip_name
  project = var.project_id
  region  = local.region

  depends_on = [google_project_service.compute]
}

resource "google_compute_global_address" "cloudsql_private_range" {
  name          = local.cloudsql_private_range_name
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.primary.id

  depends_on = [google_project_service.servicenetworking]
}

resource "google_service_networking_connection" "cloudsql_private_connection" {
  network                 = google_compute_network.primary.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql_private_range.name]

  depends_on = [
    google_project_service.servicenetworking,
    google_compute_global_address.cloudsql_private_range
  ]
}
