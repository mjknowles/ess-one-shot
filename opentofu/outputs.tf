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

output "managed_certificate_name" {
  description = "ManagedCertificate resource that fronts the public HTTPS endpoints."
  value       = kubernetes_manifest.managed_certificate.manifest.metadata.name
}

output "hosts" {
  description = "Ingress hostnames for the Element Server Suite components."
  value       = local.hostnames
}
