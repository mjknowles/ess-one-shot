terraform {
  backend "gcs" {}

  required_version = ">= 1.10.6"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.38.0"
    }
  }
}
