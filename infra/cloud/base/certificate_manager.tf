# 1️⃣ DNS Authorization in the Certificate Manager project (ess-one-shot)
resource "google_certificate_manager_dns_authorization" "base" {
  name     = local.dns_authorization_base_name
  project  = var.project_id
  location = "global"
  domain   = local.base_domain

  depends_on = [google_project_service.certificatemanager]
}

# 2️⃣ Create DNS record in your DNS project to prove control of the domain
resource "google_dns_record_set" "cert_validation" {
  provider     = google.dns
  project      = local.dns_project              # resolves to dns-infra-474704
  managed_zone = var.dns_zone_name              # "mjknowles-dev-zone"

  name    = google_certificate_manager_dns_authorization.base.dns_resource_record[0].name
  type    = google_certificate_manager_dns_authorization.base.dns_resource_record[0].type
  ttl     = 300
  rrdatas = [google_certificate_manager_dns_authorization.base.dns_resource_record[0].data]
}

# 3️⃣ Managed Certificate for both apex and wildcard domains
resource "google_certificate_manager_certificate" "gateway" {
  name     = local.certificate_name
  project  = var.project_id
  location = "global"

  managed {
    dns_authorizations = [
      google_certificate_manager_dns_authorization.base.id
    ]
    domains = local.gateway_tls_domains  # already ["mjknowles.dev", "*.mjknowles.dev"]
  }

  depends_on = [
    google_project_service.certificatemanager,
    google_dns_record_set.cert_validation
  ]
}

# 4️⃣ Certificate Map and Entries (unchanged logic)
resource "google_certificate_manager_certificate_map" "gateway" {
  name     = local.certificate_map_name
  project  = var.project_id

  depends_on = [
    google_project_service.certificatemanager,
    google_certificate_manager_certificate.gateway
  ]
}

resource "google_certificate_manager_certificate_map_entry" "base" {
  name         = local.certificate_map_entry_base_name
  project      = var.project_id
  map = google_certificate_manager_certificate_map.gateway.name
  hostname     = local.base_domain
  certificates = [google_certificate_manager_certificate.gateway.id]

  depends_on = [
    google_certificate_manager_certificate.gateway,
    google_certificate_manager_certificate_map.gateway
  ]
}

resource "google_certificate_manager_certificate_map_entry" "wildcard" {
  name         = local.certificate_map_entry_wildcard_name
  project      = var.project_id
  map = google_certificate_manager_certificate_map.gateway.name
  hostname     = "*.${local.base_domain}"
  certificates = [google_certificate_manager_certificate.gateway.id]

  depends_on = [
    google_certificate_manager_certificate.gateway,
    google_certificate_manager_certificate_map.gateway
  ]
}
