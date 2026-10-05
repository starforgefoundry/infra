locals {
  redirect_origin_ipv4 = "192.0.2.1"
}

// The redirect rule only sees traffic for hosts that are proxied.
resource "cloudflare_dns_record" "redirect" {
  for_each = var.redirects

  zone_id = var.zone_id
  name    = each.value.host
  type    = "A"
  content = local.redirect_origin_ipv4
  proxied = true
  ttl     = 1
  comment = "Redirect rule ${each.key}. Managed by Tofu."
}

// Explicit records win over the wildcard, so anything managed outside Tofu
// keeps resolving where it does today.
resource "cloudflare_dns_record" "wildcard" {
  count = var.public_ingress_ipv4 == null ? 0 : 1

  zone_id = var.zone_id
  name    = "*"
  type    = "A"
  content = var.public_ingress_ipv4
  comment = "Public ingress on vps-server. Managed by Tofu."
  proxied = false
  ttl     = 300
}

// The zone has one Redirect Rules entrypoint, so this owns every rule in it.
resource "cloudflare_ruleset" "redirects" {
  zone_id = var.zone_id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [for key, redirect in var.redirects : {
    ref         = key
    description = key
    expression  = "(http.host eq \"${redirect.host}\")"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code           = 301
        preserve_query_string = true
        target_url = {
          value = redirect.target
        }
      }
    }
  }]
}
