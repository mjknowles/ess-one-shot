variable "project_id" {
  description = "Google Cloud project ID where the Element Server Suite will be deployed."
  type        = string

  validation {
    condition     = trimspace(var.project_id) != ""
    error_message = "project_id must not be empty."
  }
}

variable "domain" {
  description = "Base domain for ESS ingress hostnames (e.g. example.com)."
  type        = string

  validation {
    condition     = trimspace(var.domain) != "" && lower(trimspace(var.domain)) != "placeholder_domain"
    error_message = "Provide a real domain name (not PLACEHOLDER_DOMAIN)."
  }
}

variable "dns_zone_name" {
  description = "Name of the Cloud DNS managed zone that serves the supplied domain."
  type        = string

  validation {
    condition     = trimspace(var.dns_zone_name) != ""
    error_message = "dns_zone_name must not be empty."
  }
}

variable "dns_project_id" {
  description = "Optional GCP project ID that owns the Cloud DNS managed zone (defaults to project_id when omitted)."
  type        = string
  default     = ""
}

