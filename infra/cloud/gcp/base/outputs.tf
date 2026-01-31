output "cluster_name" {
  description = "Name of the Autopilot GKE cluster."
  value       = google_container_cluster.autopilot.name
}

output "cluster_endpoint" {
  value = google_container_cluster.autopilot.endpoint
}

output "cluster_ca_certificate" {
  value = google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate
}

output "cluster_region" {
  description = "Region where the cluster is running."
  value       = google_container_cluster.autopilot.location
}

output "ess_namespace" {
  description = "Namespace where the Element Server Suite is installed."
  value       = kubernetes_namespace.ess.metadata[0].name
}

output "gateway_ip_address" {
  description = "Static IP address assigned to the GKE Gateway."
  value       = google_compute_global_address.gateway.address
}

output "gateway_ip_name" {
  description = "Static IP address assigned to the GKE Gateway."
  value       = google_compute_global_address.gateway.name
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

output "mautrix_signal_database_secret_name" {
  description = "Kubernetes secret that holds mautrix-signal database credentials."
  value       = kubernetes_secret.mautrix_signal_db.metadata[0].name
}

output "synapse_service_account_email" {
  description = "GCP service account used by the Synapse workload."
  value       = google_service_account.synapse.email
}

output "matrix_auth_service_account_email" {
  description = "GCP service account used by the MAS workload."
  value       = google_service_account.matrix_auth.email
}

output "base_domain" {
  description = "Base domain used for ingress hostnames."
  value       = local.base_domain
}

output "dns_project_id" {
  description = "Project that owns the Cloud DNS managed zone."
  value       = local.dns_project
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone name."
  value       = data.google_dns_managed_zone.ess.name
}

output "synapse_service_account_name" {
  description = "Kubernetes service account name for Synapse."
  value       = local.synapse_service_account_name
}

output "matrix_auth_service_account_name" {
  description = "Kubernetes service account name for MAS."
  value       = local.mas_service_account_name
}

output "synapse_database_user" {
  description = "Database user name for Synapse."
  value       = local.synapse_db_user
}

output "synapse_database_name" {
  description = "Database name for Synapse."
  value       = local.synapse_db_name
}

output "matrix_auth_database_user" {
  description = "Database user name for MAS."
  value       = local.matrix_auth_db_user
}

output "matrix_auth_database_name" {
  description = "Database name for MAS."
  value       = local.matrix_auth_db_name
}

output "mautrix_signal_database_user" {
  description = "Database user name for the mautrix-signal bridge."
  value       = local.mautrix_signal_db_user
}

output "mautrix_signal_database_name" {
  description = "Database name for the mautrix-signal bridge."
  value       = local.mautrix_signal_db_name
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

output "datastream_private_connection" {
  description = "Fully qualified name of the Datastream private connection used for CDC."
  value       = google_datastream_private_connection.cloudsql.name
}

output "datastream_publication_prefix" {
  description = "Prefix used for Datastream publications in Cloud SQL."
  value       = local.datastream_publication
}

output "datastream_replication_slot_prefix" {
  description = "Prefix used for Datastream replication slots in Cloud SQL."
  value       = local.datastream_replication_slot
}

output "datastream_replication_user" {
  description = "Replication user created for Datastream CDC."
  value       = local.replication_user_name
}

output "project_id" {
  description = "GCP project where this stack is deployed."
  value       = var.project_id
}

output "cloudsql_instance_name" {
  description = "Name of the Cloud SQL instance that hosts Synapse and MAS databases."
  value       = google_sql_database_instance.ess.name
}

output "certificate_map_name" {
  value = google_certificate_manager_certificate_map.gateway.name
}
