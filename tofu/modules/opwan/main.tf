data "opwan_account" "this" {}

locals {
  dfw_ipv4 = one([for a in data.opwan_account.this.addresses : a.ip if a.location == "dfw"])
}

resource "opwan_wireguard_key" "dfw" {}

resource "opwan_tunnel" "dfw" {
  name       = "DFW Public"
  location   = "dfw"
  public_key = opwan_wireguard_key.dfw.public_key
}

resource "opwan_address_assignment" "dfw" {
  ip        = local.dfw_ipv4
  kind      = "tunnel"
  tunnel_id = opwan_tunnel.dfw.id
}

// shop's envoy-dfp only serves 80 and 443 on this address; ICMP keeps path MTU discovery working
resource "opwan_firewall" "dfw" {
  ip             = local.dfw_ipv4
  default_action = "deny"

  rules = [
    { action = "allow", protocol = "tcp", ports = "80, 443" },
    { action = "allow", protocol = "icmp" },
  ]
}

resource "onepassword_item" "dfw_wireguard" {
  vault    = var.vault_uuid
  title    = "opwan-dfw"
  category = "password"
  password = opwan_wireguard_key.dfw.private_key

  section_map = {
    "wireguard" = {
      field_map = {
        "public_key" = {
          type  = "STRING"
          value = opwan_wireguard_key.dfw.public_key
        }
        "address" = {
          type  = "STRING"
          value = local.dfw_ipv4
        }
      }
    }
  }
}
