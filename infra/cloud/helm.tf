locals {
  ingress_annotations = {
    # Force HTTPS at the ingress layer when using ingress-nginx
    "nginx.ingress.kubernetes.io/force-ssl-redirect" = "true"
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
      className      = "nginx"
      controllerType = "ingress-nginx"
      tlsEnabled     = true
      tlsSecret      = local.ingress_tls_secret_name
      annotations    = local.ingress_annotations
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

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = local.cert_manager_namespace

  create_namespace = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 900

  values = [
    yamlencode({
      installCRDs = true
      serviceAccount = {
        annotations = {
          "iam.gke.io/gcp-service-account" = google_service_account.cert_manager.email
        }
      }
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
      }
      webhook = {
        resources = {
          requests = {
            cpu    = "50m"
            memory = "96Mi"
          }
        }
      }
      cainjector = {
        resources = {
          requests = {
            cpu    = "75m"
            memory = "128Mi"
          }
        }
      }
      startupapicheck = {
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    google_container_cluster.autopilot,
    google_service_account.cert_manager,
    google_service_account_iam_member.cert_manager_workload_identity
  ]
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "ingress-nginx"

  create_namespace = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 900

  values = [
    yamlencode({
      controller = {
        service = {
          loadBalancerIP = google_compute_address.ingress.address
          annotations = {
            "networking.gke.io/load-balancer-type" = "External"
          }
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
        admissionWebhooks = {
          createSecretJob = {
            resources = {
              requests = {
                cpu                 = "25m"
                memory              = "64Mi"
                "ephemeral-storage" = "128Mi"
              }
            }
          }
          patchWebhookJob = {
            resources = {
              requests = {
                cpu                 = "25m"
                memory              = "64Mi"
                "ephemeral-storage" = "128Mi"
              }
            }
          }
        }
      }
      defaultBackend = {
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    google_compute_address.ingress,
    google_container_cluster.autopilot
  ]
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
    google_compute_address.ingress,
    kubernetes_secret.synapse_db,
    kubernetes_secret.matrix_auth_db,
    kubernetes_manifest.ingress_certificate,
    helm_release.ingress_nginx
  ]
}
