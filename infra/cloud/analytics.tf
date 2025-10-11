resource "google_bigquery_dataset" "cdc" {
  dataset_id                  = local.analytics_dataset_id
  project                     = var.project_id
  location                    = local.analytics_location
  delete_contents_on_destroy  = false
  default_table_expiration_ms = null

  depends_on = [google_project_service.bigquery]
}

locals {
  datastream_synapse_profile_id  = substr("${local.sanitized_instance_name}-synapse-src", 0, 63)
  datastream_mas_profile_id      = substr("${local.sanitized_instance_name}-mas-src", 0, 63)
  datastream_bigquery_profile_id = substr("${local.sanitized_instance_name}-bq-dest", 0, 63)
  datastream_synapse_stream_id   = substr("${local.datastream_stream_base}-synapse", 0, 63)
  datastream_mas_stream_id       = substr("${local.datastream_stream_base}-mas", 0, 63)
}

resource "google_datastream_connection_profile" "postgres_synapse" {
  create_without_validation = true
  location                  = local.analytics_location
  project                   = var.project_id
  connection_profile_id     = local.datastream_synapse_profile_id
  display_name              = "ESS Synapse PostgreSQL"

  postgresql_profile {
    hostname = google_sql_database_instance.ess.private_ip_address
    port     = 5432
    username = local.replication_user_name
    password = random_password.replication_user.result
    database = local.synapse_db_name
  }

  depends_on = [
    google_project_service.datastream,
    google_sql_database_instance.ess
  ]
}

resource "google_datastream_connection_profile" "postgres_mas" {
  create_without_validation = true
  location                  = local.analytics_location
  project                   = var.project_id
  connection_profile_id     = local.datastream_mas_profile_id
  display_name              = "ESS MAS PostgreSQL"

  postgresql_profile {
    hostname = google_sql_database_instance.ess.private_ip_address
    port     = 5432
    username = local.replication_user_name
    password = random_password.replication_user.result
    database = local.matrix_auth_db_name
  }

  depends_on = [
    google_project_service.datastream,
    google_sql_database_instance.ess
  ]
}

resource "google_datastream_connection_profile" "bigquery" {
  create_without_validation = true
  location                  = local.analytics_location
  project                   = var.project_id
  connection_profile_id     = local.datastream_bigquery_profile_id
  display_name              = "ESS BigQuery"

  bigquery_profile {}

  depends_on = [google_project_service.datastream]
}

resource "google_datastream_stream" "synapse" {
  create_without_validation = true
  location                  = local.analytics_location
  project                   = var.project_id
  stream_id                 = local.datastream_synapse_stream_id
  display_name              = "Synapse to BigQuery"
  desired_state             = "NOT_STARTED"

  source_config {
    source_connection_profile = google_datastream_connection_profile.postgres_synapse.name

    postgresql_source_config {
      publication      = "${local.datastream_publication}_${local.synapse_db_name}"
      replication_slot = "${local.datastream_replication_slot}_${local.synapse_db_name}"
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bigquery.name

    bigquery_destination_config {
      single_target_dataset {
        dataset_id = google_bigquery_dataset.cdc.id
      }
    }
  }

  backfill_all {}

  depends_on = [
    google_datastream_connection_profile.postgres_synapse,
    google_datastream_connection_profile.bigquery
  ]
}

resource "google_datastream_stream" "matrix_auth" {
  create_without_validation = true
  location                  = local.analytics_location
  project                   = var.project_id
  stream_id                 = local.datastream_mas_stream_id
  display_name              = "MAS to BigQuery"
  desired_state             = "NOT_STARTED"

  source_config {
    source_connection_profile = google_datastream_connection_profile.postgres_mas.name

    postgresql_source_config {
      publication      = "${local.datastream_publication}_${local.matrix_auth_db_name}"
      replication_slot = "${local.datastream_replication_slot}_${local.matrix_auth_db_name}"
    }
  }

  destination_config {
    destination_connection_profile = google_datastream_connection_profile.bigquery.name

    bigquery_destination_config {
      single_target_dataset {
        dataset_id = google_bigquery_dataset.cdc.id
      }
    }
  }

  backfill_all {}

  depends_on = [
    google_datastream_connection_profile.postgres_mas,
    google_datastream_connection_profile.bigquery
  ]
}
