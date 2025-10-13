data "terraform_remote_state" "base" {
  backend = "gcs"
  config = {
    bucket = "ess-one-shot-tfstate"
    prefix = "opentofu/base"
  }
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = data.terraform_remote_state.base.outputs.cluster_endpoint
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.base.outputs.cluster_ca_certificate)
}
