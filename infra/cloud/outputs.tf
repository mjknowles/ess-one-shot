output "cluster_name" {
  description = "Name of the Autopilot GKE cluster."
  value       = google_container_cluster.autopilot.name
}

output "cluster_region" {
  description = "Region where the cluster is running."
  value       = google_container_cluster.autopilot.location
}

output "ess_namespace" {
  description = "Namespace where the Element Server Suite is installed."
  value       = kubernetes_namespace.ess.metadata[0].name
}

output "ingress_ip_address" {
  description = "Global static IP address assigned to the HTTPS load balancer."
  value       = google_compute_global_address.ingress.address
}

output "hosts" {
  description = "Ingress hostnames for the Element Server Suite components."
  value       = local.hostnames
}

output "cloudsql_instance_connection_name" {
  description = "Cloud SQL instance connection string (PROJECT:REGION:INSTANCE)."
  value       = google_sql_database_instance.ess.connection_name
}

output "cloudsql_private_ip" {
  description = "Private IP address assigned to the Cloud SQL instance."
  value       = google_sql_database_instance.ess.private_ip_address
}

output "synapse_database_secret_name" {
  description = "Kubernetes secret that holds Synapse database credentials."
  value       = kubernetes_secret.synapse_db.metadata[0].name
}

output "matrix_auth_database_secret_name" {
  description = "Kubernetes secret that holds MAS database credentials."
  value       = kubernetes_secret.matrix_auth_db.metadata[0].name
}

output "synapse_service_account_email" {
  description = "GCP service account used by the Synapse workload."
  value       = google_service_account.synapse.email
}

output "matrix_auth_service_account_email" {
  description = "GCP service account used by the MAS workload."
  value       = google_service_account.matrix_auth.email
}

output "bigquery_dataset_id" {
  description = "Dataset that receives Datastream change data capture output."
  value       = google_bigquery_dataset.cdc.id
}

output "analytics_location" {
  description = "Region where the CDC (Datastream/BigQuery) resources reside."
  value       = local.analytics_location
}

output "datastream_stream_ids" {
  description = "Identifiers for the Datastream streams created for CDC."
  value = {
    synapse = google_datastream_stream.synapse.stream_id
    mas     = google_datastream_stream.matrix_auth.stream_id
  }
}
