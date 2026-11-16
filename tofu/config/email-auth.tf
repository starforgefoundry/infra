module "email_auth" {
  source = "../modules/email-auth"

  zone_id              = local.zone_id
  domain               = local.domain
  dmarc_report_address = "ba4f5e957ae94f0faf03b59b4a869a36@dmarc-reports.cloudflare.net"
  spf_includes         = ["_spf.google.com"]
}

import {
  to = module.email_auth.cloudflare_dns_record.dmarc
  id = "${local.zone_id}/236cb45e6d190a973d42950c1986439b"
}

import {
  to = module.email_auth.cloudflare_dns_record.spf
  id = "${local.zone_id}/9a29d8fa9316f9da65c93be88ecf9202"
}
