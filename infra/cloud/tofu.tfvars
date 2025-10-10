project_id     = "ess-one-shot"
domain         = "matrix.mjknowles.dev"
dns_zone_name  = "mjknowles-dev-zone"
dns_project_id = "dns-infra-474704"
# region = "us-central1"   # optional override
# vpc_network_name = "default"  # use an existing VPC that the GKE cluster and Cloud SQL share

# --- Cloud SQL / CDC tuning (optional overrides) ---
# cloudsql_instance_name      = "ess-matrix-postgres"
# cloudsql_tier               = "db-custom-2-8192"
# cloudsql_disk_size_gb       = 100
# cloudsql_availability_type  = "ZONAL"
# cloudsql_backup_start_time  = "03:00"
# cloudsql_deletion_protection = true
# synapse_db_name             = "synapse"
# synapse_db_user             = "synapse_app"
# matrix_auth_db_name         = "mas"
# matrix_auth_db_user         = "mas_app"
# analytics_dataset_id        = "ess_matrix_cdc"
# analytics_location          = "us-central1"
# datastream_stream_id        = "ess-postgres-to-bq"
