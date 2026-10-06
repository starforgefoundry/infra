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
    wiki = {
      host   = "classes.${local.domain}"
      target = "https://orion.starforgefoundry.com/classes"
    }
  }
}
