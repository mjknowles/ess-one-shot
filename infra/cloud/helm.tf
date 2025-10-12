locals {
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
      tlsEnabled = false
    }
    serverName = local.base_domain
    elementAdmin = {
      ingress = {
        host = local.hostnames.admin
      }
      resources = {
        requests = {
          cpu    = "25m"
          memory = "64Mi"
        }
      }
    }
    elementWeb = {
      ingress = {
        host = local.hostnames.chat
      }
      resources = {
        requests = {
          cpu    = "25m"
          memory = "64Mi"
        }
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
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
      }
    }
    matrixRTC = {
      ingress = {
        host = local.hostnames.rtc
      }
      resources = {
        requests = {
          cpu    = "25m"
          memory = "32Mi"
        }
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
      resources = {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
      }
    }
  }
}
