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
