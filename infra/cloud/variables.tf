variable "project_id" {
  description = "Google Cloud project ID where the Element Server Suite will be deployed."
  type        = string

  validation {
    condition     = trimspace(var.project_id) != ""
    error_message = "project_id must not be empty."
  }
}

variable "region" {
  description = "GCP region for the Autopilot GKE cluster."
  type        = string
  default     = "us-central1"
}

variable "domain" {
  description = "Base domain for ESS ingress hostnames (e.g. example.com)."
  type        = string

  validation {
    condition     = trimspace(var.domain) != "" && lower(trimspace(var.domain)) != "placeholder_domain"
    error_message = "Provide a real domain name (not PLACEHOLDER_DOMAIN)."
  }
}

variable "cluster_name" {
  description = "Name of the Autopilot GKE cluster to create."
  type        = string
  default     = "ess-one-shot-gke"
}

variable "dns_zone_name" {
  description = "Name of the Cloud DNS managed zone that serves the supplied domain."
  type        = string

  validation {
    condition     = trimspace(var.dns_zone_name) != ""
    error_message = "dns_zone_name must not be empty."
  }
}

variable "dns_project_id" {
  description = "GCP project ID that owns the Cloud DNS managed zone. Defaults to project_id when omitted."
  type        = string
  default     = ""
}

variable "vpc_network_name" {
  description = "Existing VPC network that both GKE and Cloud SQL will use (defaults to the auto-created 'default' network)."
  type        = string
  default     = "default"
}

variable "cloudsql_instance_name" {
  description = "Name to assign to the managed Cloud SQL for PostgreSQL instance."
  type        = string
  default     = "ess-matrix-postgres"

  validation {
    condition     = trimspace(var.cloudsql_instance_name) != ""
    error_message = "cloudsql_instance_name must not be empty."
  }
}

variable "cloudsql_tier" {
  description = "Machine tier for the Cloud SQL PostgreSQL instance (e.g. db-custom-2-8192). Must support logical replication."
  type        = string
  default     = "db-custom-2-8192"
}

variable "cloudsql_disk_size_gb" {
  description = "Size in GB of the Cloud SQL data disk."
  type        = number
  default     = 100

  validation {
    condition     = var.cloudsql_disk_size_gb >= 20
    error_message = "Cloud SQL disk size must be at least 20 GB."
  }
}

variable "cloudsql_availability_type" {
  description = "Availability configuration for Cloud SQL (ZONAL or REGIONAL)."
  type        = string
  default     = "ZONAL"

  validation {
    condition     = contains(["ZONAL", "REGIONAL"], upper(var.cloudsql_availability_type))
    error_message = "cloudsql_availability_type must be either ZONAL or REGIONAL."
  }
}

variable "cloudsql_backup_start_time" {
  description = "UTC start time for automated backups (HH:MM)."
  type        = string
  default     = "03:00"
}

variable "cloudsql_deletion_protection" {
  description = "Whether to enable deletion protection on the Cloud SQL instance."
  type        = bool
  default     = true
}

variable "synapse_db_name" {
  description = "Database name to provision for Synapse within Cloud SQL."
  type        = string
  default     = "synapse"
}

variable "synapse_db_user" {
  description = "PostgreSQL user that Synapse will authenticate as."
  type        = string
  default     = "synapse_app"
}

variable "matrix_auth_db_name" {
  description = "Database name to provision for the Matrix Authentication Service."
  type        = string
  default     = "mas"
}

variable "matrix_auth_db_user" {
  description = "PostgreSQL user that the Matrix Authentication Service will use."
  type        = string
  default     = "mas_app"
}

variable "analytics_dataset_id" {
  description = "BigQuery dataset ID that will receive CDC data via Datastream."
  type        = string
  default     = "ess_matrix_cdc"
}

variable "analytics_location" {
  description = "BigQuery/Datastream location for CDC resources."
  type        = string
  default     = "us-central1"
}

variable "datastream_stream_id" {
  description = "Identifier for the Datastream stream that replicates PostgreSQL into BigQuery."
  type        = string
  default     = "ess-postgres-to-bq"
}
