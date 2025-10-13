locals {
  base_domain      = data.terraform_remote_state.base.outputs.base_domain
  hostnames        = data.terraform_remote_state.base.outputs.hostnames
  gateway_ip       = data.terraform_remote_state.base.outputs.gateway_ip
  certificate_map  = data.terraform_remote_state.base.outputs.certificate_map_name
  gateway_name     = "ess-gateway"
  gateway_listener_wildcard = "wildcard-https"
  gateway_listener_root     = "root-https"
}
