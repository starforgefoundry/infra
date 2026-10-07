locals {
  public_ingress_enabled = true

  dns_redirects = {
    waiver = {
      host   = "waiver.${local.domain}"
      target = "https://orion.starforgefoundry.com/waiver"
    }

    classes = {
      host   = "classes.${local.domain}"
      target = "https://orion.starforgefoundry.com/classes"
    }
  }
}
