locals {
  shop_subnets = [
    "10.0.10.0/24", # shop LAN
    "10.0.60.0/24", # printer VLAN
  ]
}

resource "tailscale_acl" "acls" {
  acl = jsonencode({
    tagOwners : merge(
      {
        "tag:ci" : [var.admin],

        // platform tags
        "tag:nixos" : [var.admin],
        "tag:kube-operator" : [var.admin, "tag:kube-operator"],
        "tag:kube-service" : [var.admin, "tag:kube-operator"],
      },
      // cluster tags
      { for cluster in var.clusters : "tag:${cluster}" => [var.admin, "tag:kube-operator"] },
    ),

    acls : [
      {
        action : "accept",
        src : ["*"],
        dst : ["*:*"],
      },
    ],

    autoApprovers : {
      "exitNode" : ["tag:nixos", var.admin],
      "routes" : { for subnet in local.shop_subnets : subnet => ["tag:shop"] },
      "services" : {
        for cluster in var.clusters : "svc:${cluster}-ingress" => ["tag:kube-service"]
      },
    },
  })

  overwrite_existing_content = true
}

resource "tailscale_dns_preferences" "preferences" {
  magic_dns = true
}

resource "tailscale_dns_nameservers" "nameservers" {
  nameservers = [
    "1.1.1.1",
    "1.0.0.1",
    "2606:4700:4700::1111",
    "2606:4700:4700::1001",
  ]
}

resource "tailscale_oauth_client" "operator" {
  description = "kubernetes operator"
  scopes      = ["devices:core", "auth_keys", "services"]
  tags        = ["tag:kube-operator"]

  depends_on = [tailscale_acl.acls]
}

resource "onepassword_item" "operator" {
  vault    = var.vault_uuid
  title    = "tailscale-operator"
  category = "password"

  section_map = {
    "credentials" = {
      field_map = {
        "client_id" = {
          type  = "STRING"
          value = tailscale_oauth_client.operator.id
        }
        "client_secret" = {
          type  = "CONCEALED"
          value = tailscale_oauth_client.operator.key
        }
      }
    }
  }
}
