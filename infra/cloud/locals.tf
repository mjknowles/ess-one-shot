locals {
  region                        = "us-central1"
  cluster_name                  = "ess-one-shot-gke"
  vpc_network_name              = "ess-one-shot-vpc"
  subnetwork_name               = "ess-one-shot-subnet"
  subnetwork_ip_cidr_range      = "10.10.0.0/20"
  pods_secondary_range_name     = "ess-one-shot-pods"
  pods_secondary_cidr_range     = "10.20.0.0/16"
  services_secondary_range_name = "ess-one-shot-services"
  services_secondary_cidr_range = "10.30.0.0/20"
  cloudsql_instance_name        = "ess-matrix-postgres"
  cloudsql_tier                 = "db-custom-1-3840"
  cloudsql_disk_size_gb         = 10
  cloudsql_availability_type    = "ZONAL"
  cloudsql_backup_start_time    = "03:00"
  cloudsql_deletion_protection  = false
  synapse_db_name               = "synapse"
  synapse_db_user               = "synapse_app"
  matrix_auth_db_name           = "mas"
  matrix_auth_db_user           = "mas_app"
  analytics_dataset_id          = "ess_matrix_cdc"
  analytics_location            = "us-central1"
  datastream_stream_base        = "ess-postgres-to-bq"
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

  sanitized_base_domain               = replace(local.base_domain, ".", "-")
  static_ip_name                      = "ess-gateway-ip"
  dns_project                         = trimspace(var.dns_project_id) != "" ? trimspace(var.dns_project_id) : var.project_id
  sanitized_instance_name             = join("-", regexall("[a-z0-9]+", lower(local.cloudsql_instance_name)))
  cloudsql_private_range_name         = substr("${local.sanitized_instance_name}-ps-range", 0, 62)
  synapse_service_account_name        = "synapse-db-client"
  mas_service_account_name            = "mas-db-client"
  synapse_secret_name                 = "synapse-db-credentials"
  mas_secret_name                     = "mas-db-credentials"
  replication_user_name               = "datastream_replica"
  datastream_publication              = "ess_publication"
  datastream_replication_slot         = "ess_replication_slot"
  gateway_name                        = "ess-gateway"
  gateway_listener_wildcard           = "wildcard-https"
  gateway_listener_root               = "root-https"
  certificate_name                    = "ess-gateway-certificate"
  certificate_map_name                = "ess-gateway-cert-map"
  certificate_map_entry_base_name     = "ess-base-certificate-entry"
  certificate_map_entry_wildcard_name = "ess-wildcard-certificate-entry"
  dns_authorization_base_name         = "ess-base-domain-authz"
  dns_authorization_wildcard_name     = "ess-wildcard-domain-authz"
  gateway_tls_domains = sort([
    local.base_domain,
    "*.${local.base_domain}"
  ])
}

locals {
  dns_authorizations = {
    base     = google_certificate_manager_dns_authorization.base
    wildcard = google_certificate_manager_dns_authorization.wildcard
  }
}
