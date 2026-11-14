data "cloudflare_zone" "this" {
  filter = {
    name = var.domain
  }
}

locals {
  redirect_origin_ipv4 = "192.0.2.1"
  proxied_hosts        = toset([var.domain, "*.${var.domain}"])
}

// The redirect rule only sees traffic for hosts that are proxied.
resource "cloudflare_dns_record" "redirect" {
  for_each = local.proxied_hosts

  zone_id = data.cloudflare_zone.this.id
  name    = each.key
  type    = "A"
  content = local.redirect_origin_ipv4
  proxied = true
  ttl     = 1
  comment = "Redirect to ${var.target_origin}. Managed by Tofu."
}

resource "cloudflare_ruleset" "redirect" {
  zone_id = data.cloudflare_zone.this.id
  name    = "default"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [{
    ref         = "domain_redirect"
    description = "Redirect to ${var.target_origin}"
    expression  = "true"
    action      = "redirect"
    action_parameters = {
      from_value = {
        status_code           = var.status_code
        preserve_query_string = true
        target_url = {
          expression = "concat(\"${var.target_origin}\", http.request.uri.path)"
        }
      }
    }
  }]
}
