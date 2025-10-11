resource "random_password" "synapse_db_user" {
  length           = 24
  special          = true
  override_special = "!@#%^*_-+=?"
}

resource "random_password" "matrix_auth_db_user" {
  length           = 24
  special          = true
  override_special = "!@#%^*_-+=?"
}

resource "random_password" "replication_user" {
  length           = 24
  special          = true
  override_special = "!@#%^*_-+=?"
}

resource "google_sql_database_instance" "ess" {
  name             = local.cloudsql_instance_name
  project          = var.project_id
  region           = local.region
  database_version = "POSTGRES_15"

  deletion_protection = local.cloudsql_deletion_protection

  settings {
    tier              = local.cloudsql_tier
    availability_type = upper(local.cloudsql_availability_type)
    disk_type         = "PD_SSD"
    disk_size         = local.cloudsql_disk_size_gb

    backup_configuration {
      enabled    = true
      start_time = local.cloudsql_backup_start_time
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.primary.id
      enable_private_path_for_google_cloud_services = true
    }

    maintenance_window {
      day          = 7
      hour         = 3
      update_track = "stable"
    }

    database_flags {
      name  = "cloudsql.logical_decoding"
      value = "on"
    }

    database_flags {
      name  = "max_replication_slots"
      value = "10"
    }

    database_flags {
      name  = "max_wal_senders"
      value = "10"
    }

  }

  depends_on = [
    google_project_service.sqladmin,
    google_service_networking_connection.cloudsql_private_connection
  ]
}

resource "google_sql_database" "synapse" {
  name      = local.synapse_db_name
  instance  = google_sql_database_instance.ess.name
  project   = var.project_id
  charset   = "UTF8"
  collation = "C"
}

resource "google_sql_database" "matrix_auth" {
  name      = local.matrix_auth_db_name
  instance  = google_sql_database_instance.ess.name
  project   = var.project_id
  charset   = "UTF8"
  collation = "en_US.UTF8"
}

resource "google_sql_user" "synapse" {
  name     = local.synapse_db_user
  instance = google_sql_database_instance.ess.name
  project  = var.project_id
  password = random_password.synapse_db_user.result
}

resource "google_sql_user" "matrix_auth" {
  name     = local.matrix_auth_db_user
  instance = google_sql_database_instance.ess.name
  project  = var.project_id
  password = random_password.matrix_auth_db_user.result
}

resource "google_sql_user" "replication" {
  name     = local.replication_user_name
  instance = google_sql_database_instance.ess.name
  project  = var.project_id
  password = random_password.replication_user.result
}
