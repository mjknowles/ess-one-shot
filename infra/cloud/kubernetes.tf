resource "kubernetes_namespace" "ess" {
  metadata {
    name = "ess"
  }
}

resource "kubernetes_secret" "synapse_db" {
  metadata {
    name      = local.synapse_secret_name
    namespace = kubernetes_namespace.ess.metadata[0].name
  }

  type = "Opaque"

  data = {
    username = local.synapse_db_user
    password = random_password.synapse_db_user.result
    database = local.synapse_db_name
    host     = google_sql_database_instance.ess.private_ip_address
    port     = "5432"
  }

  depends_on = [
    kubernetes_namespace.ess,
    google_sql_user.synapse,
    google_sql_database.synapse
  ]
}

resource "kubernetes_secret" "matrix_auth_db" {
  metadata {
    name      = local.mas_secret_name
    namespace = kubernetes_namespace.ess.metadata[0].name
  }

  type = "Opaque"

  data = {
    username = local.matrix_auth_db_user
    password = random_password.matrix_auth_db_user.result
    database = local.matrix_auth_db_name
    host     = google_sql_database_instance.ess.private_ip_address
    port     = "5432"
  }

  depends_on = [
    kubernetes_namespace.ess,
    google_sql_user.matrix_auth
  ]
}

resource "kubernetes_manifest" "letsencrypt_cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = local.cert_manager_cluster_issuer_name
    }
    spec = {
      acme = {
        email  = var.acme_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = local.cert_manager_cluster_issuer_secret_name
        }
        solvers = [
          {
            dns01 = {
              cloudDNS = {
                project     = local.dns_project
                managedZone = data.google_dns_managed_zone.ess.name
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager,
    google_service_account_iam_member.cert_manager_workload_identity,
    google_project_iam_member.cert_manager_dns_admin
  ]
}

resource "kubernetes_manifest" "ingress_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = local.ingress_tls_certificate_name
      namespace = kubernetes_namespace.ess.metadata[0].name
    }
    spec = {
      secretName = local.ingress_tls_secret_name
      issuerRef = {
        name = local.cert_manager_cluster_issuer_name
        kind = "ClusterIssuer"
      }
      dnsNames = local.ingress_tls_dns_names
    }
  }

  depends_on = [
    kubernetes_namespace.ess,
    kubernetes_manifest.letsencrypt_cluster_issuer
  ]
}
