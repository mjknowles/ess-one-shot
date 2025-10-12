resource "google_certificate_manager_dns_authorization" "base" {
  name     = local.dns_authorization_base_name
  project  = var.project_id
  location = "global"
  domain   = local.base_domain

  depends_on = [google_project_service.certificatemanager]
}

resource "google_certificate_manager_dns_authorization" "wildcard" {
  name     = local.dns_authorization_wildcard_name
  project  = var.project_id
  location = "global"
  domain   = "*.${local.base_domain}"

  depends_on = [google_project_service.certificatemanager]
}

resource "google_certificate_manager_certificate" "gateway" {
  name     = local.certificate_name
  project  = var.project_id
  location = "global"

  managed {
    dns_authorizations = [
      google_certificate_manager_dns_authorization.base.id,
      google_certificate_manager_dns_authorization.wildcard.id
    ]
    domains = local.gateway_tls_domains
  }

  depends_on = [
    google_project_service.certificatemanager,
    google_certificate_manager_dns_authorization.base,
    google_certificate_manager_dns_authorization.wildcard
  ]
}

resource "google_certificate_manager_certificate_map" "gateway" {
  name     = local.certificate_map_name
  project  = var.project_id

  depends_on = [
    google_project_service.certificatemanager,
    google_certificate_manager_certificate.gateway
  ]
}

resource "google_certificate_manager_certificate_map_entry" "base" {
  name     = local.certificate_map_entry_base_name
  project  = var.project_id
  map      = google_certificate_manager_certificate_map.gateway.id
  hostname = local.base_domain

  certificates = [google_certificate_manager_certificate.gateway.id]

  depends_on = [
    google_certificate_manager_certificate.gateway,
    google_certificate_manager_certificate_map.gateway
  ]
}

resource "google_certificate_manager_certificate_map_entry" "wildcard" {
  name     = local.certificate_map_entry_wildcard_name
  project  = var.project_id
  map      = google_certificate_manager_certificate_map.gateway.id
  hostname = "*.${local.base_domain}"

  certificates = [google_certificate_manager_certificate.gateway.id]

  depends_on = [
    google_certificate_manager_certificate.gateway,
    google_certificate_manager_certificate_map.gateway
  ]
}
