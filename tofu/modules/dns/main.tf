resource "cloudflare_dns_record" "this" {
  for_each = var.records

  zone_id  = var.zone_id
  name     = each.value.name
  type     = each.value.type
  content  = each.value.content
  ttl      = each.value.ttl
  proxied  = each.value.proxied
  priority = each.value.priority
}

// Explicit records win over the wildcard, so the website and anything else in
// var.records keep resolving where they do today.
resource "cloudflare_dns_record" "wildcard" {
  count = var.public_ingress_ipv4 == null ? 0 : 1

  zone_id = var.zone_id
  name    = "*"
  type    = "A"
  content = var.public_ingress_ipv4
  comment = "Public ingress on starforge-vps. Managed by Tofu."
  proxied = false
  ttl     = 300
}
