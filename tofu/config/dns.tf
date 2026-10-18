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

    carbay = {
      host   = "carbay.${local.domain}"
      target = "https://orion.starforgefoundry.com/car_bay"
    }

    pass = {
      host   = "pass.${local.domain}"
      target = "https://orion.starforgefoundry.com/pass"
    }

    print_request = {
      host   = "3dprint.${local.domain}"
      target = "https://orion.starforgefoundry.com/print_request"
    }
  }
}
