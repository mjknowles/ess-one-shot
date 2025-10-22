provider "google" {
  project = var.project_id
  region  = local.region
}

data "google_client_config" "current" {}

data "google_project" "current" {
  project_id = var.project_id
}

provider "google" {
  alias   = "dns"
  project = local.dns_project
  region  = local.region
}
