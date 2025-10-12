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

  rrdatas = [google_compute_global_address.gateway.address]
}

resource "google_dns_record_set" "certificate_dns_authorizations" {
  for_each = {
    base     = google_certificate_manager_dns_authorization.base.dns_resource_record
    wildcard = google_certificate_manager_dns_authorization.wildcard.dns_resource_record
  }

  provider = google.dns

  name         = each.value.name
  type         = each.value.type
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.ess.name
  project      = local.dns_project

  rrdatas = [each.value.data]
}
