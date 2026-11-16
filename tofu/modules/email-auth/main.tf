resource "cloudflare_dns_record" "dmarc" {
  zone_id = var.zone_id
  name    = "_dmarc.${var.domain}"
  type    = "TXT"
  content = "\"v=DMARC1; p=none; rua=mailto:${var.dmarc_report_address}\""
  ttl     = 3600
  comment = "Reports go to Cloudflare DMARC Management. Managed by Tofu."
}
