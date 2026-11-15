module "resend" {
  source = "../modules/resend"

  zone_id         = local.zone_id
  domain          = local.domain
  dkim_public_key = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCm3VM5yUJ9iFYMCF/U8HGhmdO2D2C5fGsDpuCCuIud8G1/R0RFWK8ClSL4Nybax0QZvAT+O5anJACpn15Z778AAA/lR0XJFoRnWd9nF0aphYkLM377VdLogIlryldbSupCdyUgw9oEHw1/1Kr3IP9AtiswT0g/zRiurKpSxSDilwIDAQAB"
}

import {
  to = module.resend.cloudflare_dns_record.dkim
  id = "${local.zone_id}/efb2e357077d5b09a9e58983b4abf5b8"
}

import {
  to = module.resend.cloudflare_dns_record.send
  id = "${local.zone_id}/a72bee806143ef89075cae1c78213878"
}

import {
  to = module.resend.cloudflare_dns_record.rsend
  id = "${local.zone_id}/13a930d9b43a1e9ffd9030d6453566ae"
}
