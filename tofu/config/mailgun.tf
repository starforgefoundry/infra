resource "cloudflare_dns_record" "mailgun_tracking" {
  zone_id = local.zone_id
  name    = "email.${local.domain}"
  type    = "CNAME"
  content = "mailgun.org"
  proxied = false
  ttl     = 3600
}

resource "cloudflare_dns_record" "mailgun_dkim" {
  zone_id = local.zone_id
  name    = "mx._domainkey.${local.domain}"
  type    = "TXT"
  content = "\"k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC6H8JqOX2DXXccDfapzAg8LTJXMfWsp1tibh6v6KbcSWC2eqqz0NB1raLvJv/l6ZsG+zl6rm6vFUJlqLDw+goomarsniMHYBzn3iIte2dUb3ZpOEK3qYoFRKDxQ+3GM0ZN5/jKztWoiQ0gkS98UAdcCI4MtBQoJDW9PN6aSP12PQIDAQAB\""
  ttl     = 3600
}

import {
  to = cloudflare_dns_record.mailgun_tracking
  id = "${local.zone_id}/1c6d84890ec92d1224176affd9a12ceb"
}

import {
  to = cloudflare_dns_record.mailgun_dkim
  id = "${local.zone_id}/92ea35dbc15881cf421b8444d5e4e7a5"
}
