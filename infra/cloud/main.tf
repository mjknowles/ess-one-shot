locals {
  region                       = "us-central1"
  cluster_name                 = "ess-one-shot-gke"
  vpc_network_name             = "default"
  cloudsql_instance_name       = "ess-matrix-postgres"
  cloudsql_tier                = "db-custom-2-8192"
  cloudsql_disk_size_gb        = 100
  cloudsql_availability_type   = "ZONAL"
  cloudsql_backup_start_time   = "03:00"
  cloudsql_deletion_protection = true
  synapse_db_name              = "synapse"
  synapse_db_user              = "synapse_app"
  matrix_auth_db_name          = "mas"
  matrix_auth_db_user          = "mas_app"
  analytics_dataset_id         = "ess_matrix_cdc"
  analytics_location           = "us-central1"
  datastream_stream_base       = "ess-postgres-to-bq"
}

locals {
  base_domain = trimsuffix(trimspace(var.domain), ".")

  hostnames = {
    admin   = "admin.${local.base_domain}"
    chat    = "chat.${local.base_domain}"
    matrix  = "matrix.${local.base_domain}"
    account = "account.${local.base_domain}"
    rtc     = "rtc.${local.base_domain}"
  }

  managed_certificate_name = "ess-managed-cert"
  static_ip_name           = "ess-ingress-ip"
  dns_project              = trimspace(var.dns_project_id) != "" ? trimspace(var.dns_project_id) : var.project_id

  sanitized_instance_name      = regexreplace(lower(local.cloudsql_instance_name), "[^a-z0-9-]", "-")
  cloudsql_private_range_name  = substr("${local.sanitized_instance_name}-ps-range", 0, 62)
  synapse_service_account_name = "synapse-db-client"
  mas_service_account_name     = "mas-db-client"
  synapse_secret_name          = "synapse-db-credentials"
  mas_secret_name              = "mas-db-credentials"
  replication_user_name        = "datastream_replica"
  datastream_publication       = "ess_publication"
  datastream_replication_slot  = "ess_replication_slot"
}

provider "google" {
  project = var.project_id
  region  = local.region
}

data "google_client_config" "current" {}

provider "google" {
  alias   = "dns"
  project = local.dns_project
}

resource "google_project_service" "compute" {
  project                    = var.project_id
  service                    = "compute.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "container" {
  project                    = var.project_id
  service                    = "container.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "servicenetworking" {
  project                    = var.project_id
  service                    = "servicenetworking.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "sqladmin" {
  project                    = var.project_id
  service                    = "sqladmin.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "secretmanager" {
  project                    = var.project_id
  service                    = "secretmanager.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "datastream" {
  project                    = var.project_id
  service                    = "datastream.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

resource "google_project_service" "bigquery" {
  project                    = var.project_id
  service                    = "bigquery.googleapis.com"
  disable_on_destroy         = false
  disable_dependent_services = false
}

data "google_compute_network" "primary" {
  name    = local.vpc_network_name
  project = var.project_id
}

resource "google_compute_global_address" "ingress" {
  name    = local.static_ip_name
  project = var.project_id

  depends_on = [google_project_service.compute]
}

resource "google_compute_global_address" "cloudsql_private_range" {
  name          = local.cloudsql_private_range_name
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = data.google_compute_network.primary.id

  depends_on = [google_project_service.servicenetworking]
}

resource "google_service_networking_connection" "cloudsql_private_connection" {
  network                 = data.google_compute_network.primary.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql_private_range.name]

  depends_on = [
    google_project_service.servicenetworking,
    google_compute_global_address.cloudsql_private_range
  ]
}

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
      private_network                               = data.google_compute_network.primary.id
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

    database_flags {
      name  = "wal_keep_size"
      value = "2048"
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
  collation = "en_US.UTF8"
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

resource "google_container_cluster" "autopilot" {
  name     = local.cluster_name
  project  = var.project_id
  location = local.region

  enable_autopilot = true

  depends_on = [
    google_project_service.compute,
    google_project_service.container
  ]
}

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

locals {
  cluster_endpoint            = "https://${google_container_cluster.autopilot.endpoint}"
  cluster_ca                  = base64decode(google_container_cluster.autopilot.master_auth[0].cluster_ca_certificate)
  workload_identity_namespace = google_container_cluster.autopilot.workload_identity_config[0].identity_namespace
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = local.cluster_ca
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = local.cluster_ca
  }
}

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
    google_sql_user.synapse
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

locals {
  ingress_annotations = {
    "networking.gke.io/managed-certificates"      = local.managed_certificate_name
    "kubernetes.io/ingress.global-static-ip-name" = google_compute_global_address.ingress.name
  }

  cloudsql_postgres = {
    host = google_sql_database_instance.ess.private_ip_address
    port = 5432
  }

  synapse_service_account_block = {
    create = true
    name   = local.synapse_service_account_name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.synapse.email
    }
  }

  matrix_auth_service_account_block = {
    create = true
    name   = local.mas_service_account_name
    annotations = {
      "iam.gke.io/gcp-service-account" = google_service_account.matrix_auth.email
    }
  }

  ess_values = {
    postgres = {
      enabled = false
    }
    ingress = {
      className      = "gce"
      controllerType = null
      tlsEnabled     = true
      annotations    = local.ingress_annotations
    }
    serverName = local.base_domain
    elementAdmin = {
      ingress = {
        host = local.hostnames.admin
      }
    }
    elementWeb = {
      ingress = {
        host = local.hostnames.chat
      }
    }
    matrixAuthenticationService = {
      ingress = {
        host = local.hostnames.account
      }
      postgres = {
        host     = local.cloudsql_postgres.host
        port     = local.cloudsql_postgres.port
        user     = local.matrix_auth_db_user
        database = local.matrix_auth_db_name
        sslMode  = "require"
        password = {
          secret    = kubernetes_secret.matrix_auth_db.metadata[0].name
          secretKey = "password"
        }
      }
      serviceAccount = local.matrix_auth_service_account_block
    }
    matrixRTC = {
      ingress = {
        host = local.hostnames.rtc
      }
    }
    synapse = {
      ingress = {
        host = local.hostnames.matrix
      }
      postgres = {
        host     = local.cloudsql_postgres.host
        port     = local.cloudsql_postgres.port
        user     = local.synapse_db_user
        database = local.synapse_db_name
        sslMode  = "require"
        password = {
          secret    = kubernetes_secret.synapse_db.metadata[0].name
          secretKey = "password"
        }
      }
      serviceAccount = local.synapse_service_account_block
    }
  }
}

resource "helm_release" "ess" {
  name       = "ess"
  repository = "oci://ghcr.io/element-hq/ess-helm"
  chart      = "matrix-stack"
  namespace  = kubernetes_namespace.ess.metadata[0].name

  create_namespace = false
  cleanup_on_fail  = true
  wait             = true

  values = [
    yamlencode(local.ess_values)
  ]

  depends_on = [
    kubernetes_manifest.managed_certificate,
    google_compute_global_address.ingress,
    kubernetes_secret.synapse_db,
    kubernetes_secret.matrix_auth_db
  ]
}

data "google_dns_managed_zone" "ess" {
  provider = google.dns
  name     = var.dns_zone_name
}

resource "google_dns_record_set" "ess_hosts" {
  for_each = local.hostnames
  provider = google.dns

  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.ess.name
  project      = local.dns_project

  rrdatas = [google_compute_global_address.ingress.address]
}
