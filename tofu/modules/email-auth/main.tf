resource "cloudflare_dns_record" "dmarc" {
  zone_id = var.zone_id
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:${var.dmarc_report_address}\""
  ttl     = 3600
  comment = "Reports go to Cloudflare DMARC Management. Managed by Tofu."
}

resource "cloudflare_dns_record" "spf" {
  zone_id = var.zone_id
  name    = var.domain
  type    = "TXT"
  content = "\"v=spf1 ${join(" ", [for sender in var.spf_includes : "include:${sender}"])} ~all\""
  ttl     = 3600
  comment = "Root SPF. Resend uses its own SPF on send.${var.domain}. Managed by Tofu."
}
