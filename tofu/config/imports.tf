import {
  to = module.contabo.contabo_instance.starforge_vps
  id = "28982" # Contabo instance ID from the panel
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
