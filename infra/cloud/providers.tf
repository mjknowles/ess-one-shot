provider "google" {
  project = var.project_id
  region  = local.region
}

data "google_client_config" "current" {}

provider "google" {
  alias   = "dns"
  project = local.dns_project
}
