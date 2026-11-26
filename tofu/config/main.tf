module "contabo" {
  source = "../modules/contabo"
}

module "opwan" {
  source = "../modules/opwan"

  vault_uuid = local.vault_uuid
}

module "dns" {
  source = "../modules/dns"

  zone_id             = local.zone_id
  redirects           = local.dns_redirects
  public_ingress_ipv4 = local.public_ingress_enabled ? module.opwan.dfw_ipv4 : null
}

module "api_tokens" {
  source = "../modules/api-tokens"

  account_id = local.account_id
  zone_id    = local.zone_id
  vault_uuid = local.vault_uuid
}

module "fuckmesh_pages" {
  source = "../modules/pages-project"

  account_id = local.account_id
  zone_id    = local.zone_id
  name       = "fuckmesh"
  hostname   = "fuckmesh.${local.domain}"
}

module "restic" {
  source = "../modules/restic"

  account_id  = local.account_id
  vault_uuid  = local.vault_uuid
  bucket_name = "volsync"
}

module "tailscale" {
  source = "../modules/tailscale"

  clusters   = toset(local.clusters)
  admin      = "bwees@starforgefoundry.com"
  vault_uuid = local.vault_uuid
}

module "bind9_tsig" {
  source = "../modules/bind9-tsig"

  vault_uuid = local.vault_uuid
}

module "flux_webhooks" {
  source = "../modules/flux-webhooks"

  clusters   = toset(local.clusters)
  repository = "infra"
  domain     = local.domain
  vault_uuid = local.vault_uuid
}

module "domain_redirect" {
  source   = "../modules/domain-redirect"
  for_each = local.redirect_domains

  domain        = each.key
  target_origin = "https://${local.domain}"
}
