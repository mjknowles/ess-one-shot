locals {
  certificate_domains = local.certificate_domains_list
  certificate_map_hostnames = {
    wildcard = "*.${local.base_domain}"
    root     = local.base_domain
  }
  certificate_dns_authorization_name = substr(
    "${local.certificate_dns_authorization_prefix}-${replace(local.base_domain, ".", "-")}",
    0,
    63
  )
}

resource "google_certificate_manager_dns_authorization" "ess" {
  name   = local.certificate_dns_authorization_name
  domain = local.base_domain

  depends_on = [google_project_service.certificatemanager]
}

resource "google_dns_record_set" "certificate_authorization" {
  provider = google.dns

  name         = google_certificate_manager_dns_authorization.ess.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.ess.dns_resource_record[0].type
  ttl          = 60
  managed_zone = data.google_dns_managed_zone.ess.name
  project      = local.dns_project
  rrdatas      = [google_certificate_manager_dns_authorization.ess.dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "ess" {
  name = local.certificate_name

  managed {
    domains            = local.certificate_domains
    dns_authorizations = [google_certificate_manager_dns_authorization.ess.id]
  }

  depends_on = [
    google_dns_record_set.certificate_authorization,
    google_project_service.certificatemanager
  ]
}

resource "google_certificate_manager_certificate_map" "ess" {
  name = local.certificate_map_name

  depends_on = [google_project_service.certificatemanager]
}

resource "google_certificate_manager_certificate_map_entry" "ess" {
  for_each = local.certificate_map_hostnames

  name         = substr("${local.certificate_map_name}-${each.key}", 0, 63)
  map          = google_certificate_manager_certificate_map.ess.name
  hostname     = each.value
  certificates = [google_certificate_manager_certificate.ess.id]

  depends_on = [google_certificate_manager_certificate.ess]
}
