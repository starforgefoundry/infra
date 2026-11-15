locals {
  ttl = 3600
}

resource "cloudflare_dns_record" "dkim" {
  zone_id = var.zone_id
  name    = "resend._domainkey.${var.domain}"
  type    = "TXT"
  content = "\"p=${var.dkim_public_key}\""
  ttl     = local.ttl
  comment = "Resend DKIM. Managed by Tofu."
}

resource "cloudflare_dns_record" "send" {
  zone_id = var.zone_id
  name    = "send.${var.domain}"
  type    = "CNAME"
  content = "send.forge.rmta.net"
  proxied = false
  ttl     = local.ttl
  comment = "Resend bounce and SPF domain. Managed by Tofu."
}

resource "cloudflare_dns_record" "rsend" {
  zone_id = var.zone_id
  name    = "rsend.${var.domain}"
  type    = "CNAME"
  content = "rsend.forge.rmta.net"
  proxied = false
  ttl     = local.ttl
  comment = "Resend. Managed by Tofu."
}
