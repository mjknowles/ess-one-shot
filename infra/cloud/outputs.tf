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
  description = "Static IP address assigned to the ingress-nginx LoadBalancer service."
  value       = google_compute_address.ingress.address
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

output "base_domain" {
  description = "Base domain used for ingress hostnames."
  value       = local.base_domain
}

output "acme_email" {
  description = "ACME contact email for Let's Encrypt."
  value       = var.acme_email
}

output "dns_project_id" {
  description = "Project that owns the Cloud DNS managed zone."
  value       = local.dns_project
}

output "dns_zone_name" {
  description = "Cloud DNS managed zone name."
  value       = data.google_dns_managed_zone.ess.name
}

output "cert_manager_namespace" {
  description = "Namespace used for cert-manager components."
  value       = local.cert_manager_namespace
}

output "cert_manager_service_account_name" {
  description = "Kubernetes service account name for cert-manager."
  value       = local.cert_manager_service_account_name
}

output "cert_manager_service_account_email" {
  description = "GCP service account annotated onto the cert-manager service account."
  value       = google_service_account.cert_manager.email
}

output "cert_manager_cluster_issuer_name" {
  description = "Name of the ClusterIssuer used for Let's Encrypt."
  value       = local.cert_manager_cluster_issuer_name
}

output "cert_manager_cluster_issuer_secret_name" {
  description = "Secret that stores the ACME account private key."
  value       = local.cert_manager_cluster_issuer_secret_name
}

output "ingress_tls_secret_name" {
  description = "Secret that stores the wildcard TLS certificate."
  value       = local.ingress_tls_secret_name
}

output "ingress_tls_certificate_name" {
  description = "Name of the cert-manager Certificate resource."
  value       = local.ingress_tls_certificate_name
}

output "ingress_tls_dns_names" {
  description = "DNS names covered by the wildcard TLS certificate."
  value       = local.ingress_tls_dns_names
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
