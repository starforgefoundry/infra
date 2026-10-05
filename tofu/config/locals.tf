data "cloudflare_zone" "starforgefoundry_com" {
  filter = {
    name = local.domain
  }
}

data "onepassword_vault" "starforge_deployment" {
  name = local.vault_name
}

locals {
  domain       = "starforgefoundry.com"
  vault_name   = "Starforge Deployment"
  github_owner = "starforgefoundry"
  tailnet      = "tail04f5a4.ts.net"
  clusters     = ["shop", "vps"]

  account_id = data.cloudflare_zone.starforgefoundry_com.account.id
  zone_id    = data.cloudflare_zone.starforgefoundry_com.id
  vault_uuid = data.onepassword_vault.starforge_deployment.uuid
}
