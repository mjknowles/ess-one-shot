resource "kubernetes_namespace" "ess" {
  metadata {
    name = "ess"
  }
}

resource "kubernetes_manifest" "managed_certificate" {
  manifest = {
    apiVersion = "networking.gke.io/v1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = local.managed_certificate_name
      namespace = kubernetes_namespace.ess.metadata[0].name
    }
    spec = {
      domains = [
        local.hostnames.chat,
        local.hostnames.admin,
        local.hostnames.matrix,
        local.hostnames.account,
        local.hostnames.rtc,
      ]
    }
  }

  depends_on = [kubernetes_namespace.ess]
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
