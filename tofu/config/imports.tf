import {
  to = module.contabo.contabo_instance.starforge_vps
  id = "203635201"
}

// Starts from the tailnet's current policy so the first plan shows the diff
// against it instead of blindly replacing it.
import {
  to = module.tailscale.tailscale_acl.acls
  id = "acl"
}

import {
  for_each = local.dns_record_ids
  to       = module.dns.cloudflare_dns_record.this[each.key]
  id       = each.value
}

import {
  to = module.dns.cloudflare_ruleset.redirects
  id = "zones/${local.zone_id}/0d3c55fa442d40a5af196616123b0131"
}
