// Only records tied to this repo live here. Mail, verification and website
// records are managed by hand in Cloudflare.
//
// Not here on purpose:
//   - orion: a Worker custom domain, owned by the Worker
//   - orion-data: an R2 custom domain, owned by the bucket
locals {
  public_ingress_enabled = true

  dns_redirects = {
    waiver = {
      host   = "waiver.${local.domain}"
      target = "https://orion.starforgefoundry.com/waiver"
    }
    wiki = {
      host   = "wiki.${local.domain}"
      target = "https://starforge.notion.site/Starforge-Wiki-d75b4653249d4599b3c44e953cda5c6e"
    }
  }
}
