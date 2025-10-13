data "google_dns_managed_zone" "ess" {
  provider = google.dns
  name     = var.dns_zone_name
}

# A records for your hostnames
resource "google_dns_record_set" "ess_hosts" {
  for_each = local.hostnames
  provider = google.dns                    # <— CRUCIAL

  name         = "${each.value}."
  type         = "A"
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.ess.name
  project      = local.dns_project

  rrdatas = [google_compute_global_address.gateway.address]
}

# Certificate Manager DNS challenge records
resource "google_dns_record_set" "certificate_dns_authorizations" {
  for_each = local.dns_authorizations
  provider = google.dns                    # <— CRUCIAL

  name         = each.value.dns_resource_record[0].name
  type         = each.value.dns_resource_record[0].type
  ttl          = 300
  managed_zone = data.google_dns_managed_zone.ess.name
  project      = local.dns_project

  rrdatas = [each.value.dns_resource_record[0].data]
}
