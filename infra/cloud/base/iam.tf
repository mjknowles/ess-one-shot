resource "google_service_account" "synapse" {
  project      = var.project_id
  account_id   = "ess-synapse-db"
  display_name = "ESS Synapse Database Client"
}

resource "google_service_account" "matrix_auth" {
  project      = var.project_id
  account_id   = "ess-mas-db"
  display_name = "ESS Matrix Authentication Service Database Client"
}

resource "google_project_iam_member" "synapse_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.synapse.email}"
}

resource "google_project_iam_member" "matrix_auth_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.matrix_auth.email}"
}

resource "google_project_iam_member" "datastream_network_admin" {
  project = var.project_id
  role    = "roles/compute.networkAdmin"
  member  = "serviceAccount:${local.datastream_service_agent_email}"

  depends_on = [google_project_service.datastream]
}

resource "google_project_iam_member" "datastream_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${local.datastream_service_agent_email}"

  depends_on = [google_project_service.datastream]
}

resource "google_service_account_iam_member" "synapse_workload_identity" {
  service_account_id = google_service_account.synapse.name
  role               = "roles/iam.workloadIdentityUser"
  member             = format("serviceAccount:%s[%s/%s]", local.workload_identity_namespace, kubernetes_namespace.ess.metadata[0].name, local.synapse_service_account_name)

  depends_on = [
    google_container_cluster.autopilot,
    kubernetes_namespace.ess
  ]
}

resource "google_service_account_iam_member" "matrix_auth_workload_identity" {
  service_account_id = google_service_account.matrix_auth.name
  role               = "roles/iam.workloadIdentityUser"
  member             = format("serviceAccount:%s[%s/%s]", local.workload_identity_namespace, kubernetes_namespace.ess.metadata[0].name, local.mas_service_account_name)

  depends_on = [
    google_container_cluster.autopilot,
    kubernetes_namespace.ess
  ]
}
