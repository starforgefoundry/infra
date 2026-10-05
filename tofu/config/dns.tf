// Every record that exists in the zone today, imported rather than created so
// mail keeps flowing. `mise run tofu:dns-export` lists them with their IDs.
// The plan must be empty before the first apply.
//
// Not here on purpose:
//   - orion: a Worker custom domain, owned by the Worker
//   - orion-data: an R2 custom domain, owned by the bucket
//   - bambu-connect, cam, hass, print: Cloudflare Tunnel CNAMEs, deleted by
//     hand with the tunnel at cutover
locals {
  public_ingress_enabled = true

  // Each host also needs a proxied record in dns_records for the rule to see it.
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

  dns_records = {
    apex = {
      name    = local.domain
      type    = "A"
      content = "199.34.228.171"
      ttl     = 3600
    }
    www = {
      name    = "www.${local.domain}"
      type    = "CNAME"
      content = local.domain
      ttl     = 3600
    }
    waiver = {
      name    = "waiver.${local.domain}"
      type    = "A"
      content = "192.0.2.1"
      proxied = true
    }
    wiki = {
      name    = "wiki.${local.domain}"
      type    = "A"
      content = "192.0.2.1"
      proxied = true
      comment = "Wiki subdomain for CF worker"
    }
    mx = {
      name     = local.domain
      type     = "MX"
      content  = "smtp.google.com"
      priority = 1
    }
    spf = {
      name    = local.domain
      type    = "TXT"
      content = "\"v=spf1 include:_spf.google.com include:mailgun.org ~all\""
      ttl     = 3600
    }
    apple_verification = {
      name    = local.domain
      type    = "TXT"
      content = "\"apple-domain-verification=Xk5LgQyYqBacTS0M\""
    }
    dmarc = {
      name    = "_dmarc.${local.domain}"
      type    = "TXT"
      content = "\"v=DMARC1; p=none; pct=100; fo=1; ri=3600; rua=mailto:f45a103b@dmarc.mailgun.org,mailto:6cff95db@inbox.ondmarc.com; ruf=mailto:f45a103b@dmarc.mailgun.org,mailto:6cff95db@inbox.ondmarc.com;\""
    }
    google_dkim = {
      name    = "google._domainkey.${local.domain}"
      type    = "TXT"
      content = "\"v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAotcq8hnTeHZifnWt8rBd7o4URjUU5n+ImutOVeMfDOpt0tWiOSQznvVh8MHPSERZOFQQAV8s3a/E4FBo/i2R10yBvfHoAc6IpdkMVv6gIDja+gRz4tQMveb/j9jmLM12c+zOP0rfefKvJxgYy2cLPI6WlKWxNYwg91Tpk6hu2spiswe8i5I0kkZSj/XxOj2c5\" \"XPHwlBRMCq8++noZPvbJ8sdc4SM0m3Q1h3ZR+z7AIn6r+eiklpDkvlIphroYwbI7BgOryjCLmc7IdetFFpubx8/ZEXQ+S6O1H3TNbAVT/PjRzOoPmXJntAG1OmngMpDB7Ywba95duBiQflBy6tiYwIDAQAB\""
    }
    mailgun = {
      name    = "email.${local.domain}"
      type    = "CNAME"
      content = "mailgun.org"
      ttl     = 3600
    }
    mailgun_dkim = {
      name    = "mx._domainkey.${local.domain}"
      type    = "TXT"
      content = "\"k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC6H8JqOX2DXXccDfapzAg8LTJXMfWsp1tibh6v6KbcSWC2eqqz0NB1raLvJv/l6ZsG+zl6rm6vFUJlqLDw+goomarsniMHYBzn3iIte2dUb3ZpOEK3qYoFRKDxQ+3GM0ZN5/jKztWoiQ0gkS98UAdcCI4MtBQoJDW9PN6aSP12PQIDAQAB\""
      ttl     = 3600
    }
  }

  // "<zone_id>/<record_id>" for every key in dns_records
  dns_record_ids = {
    apex               = "f138fbbced62f07e46238d5f5beaab4e/b812d1020978b1d21f4b4d8c0ec4b697"
    www                = "f138fbbced62f07e46238d5f5beaab4e/a5184018786e90b62eacf392b8f7a369"
    waiver             = "f138fbbced62f07e46238d5f5beaab4e/2e9e45bf64f529395af7338b9fb60c7d"
    wiki               = "f138fbbced62f07e46238d5f5beaab4e/4068237b9dabc8d55f93ef5361dd0b15"
    mx                 = "f138fbbced62f07e46238d5f5beaab4e/2ff4d25adc2b0850c543ae459fadd2a0"
    spf                = "f138fbbced62f07e46238d5f5beaab4e/9a29d8fa9316f9da65c93be88ecf9202"
    apple_verification = "f138fbbced62f07e46238d5f5beaab4e/16ae02d51b67c713f56e1898c9545507"
    dmarc              = "f138fbbced62f07e46238d5f5beaab4e/236cb45e6d190a973d42950c1986439b"
    google_dkim        = "f138fbbced62f07e46238d5f5beaab4e/92b861dccb0e7e5e0e20879a75c8e23f"
    mailgun            = "f138fbbced62f07e46238d5f5beaab4e/1c6d84890ec92d1224176affd9a12ceb"
    mailgun_dkim       = "f138fbbced62f07e46238d5f5beaab4e/92ea35dbc15881cf421b8444d5e4e7a5"
  }
}
