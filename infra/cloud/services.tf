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

resource "google_project_service" "servicenetworking" {
  project                    = var.project_id
  service                    = "servicenetworking.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "sqladmin" {
  project                    = var.project_id
  service                    = "sqladmin.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "secretmanager" {
  project                    = var.project_id
  service                    = "secretmanager.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "datastream" {
  project                    = var.project_id
  service                    = "datastream.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "bigquery" {
  project                    = var.project_id
  service                    = "bigquery.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "certificatemanager" {
  project                    = var.project_id
  service                    = "certificatemanager.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}
