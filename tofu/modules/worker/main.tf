resource "cloudflare_worker" "this" {
  account_id = var.account_id
  name       = var.name
}

resource "cloudflare_workers_custom_domain" "this" {
  account_id = var.account_id
  zone_id    = var.zone_id
  hostname   = var.hostname
  service    = cloudflare_worker.this.name
}
