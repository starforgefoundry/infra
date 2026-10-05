// Every record that exists in the zone today, imported rather than created so
// mail keeps flowing. `mise run tofu:dns-export` lists them with their IDs.
// The plan must be empty before the first apply.
//
// Not here on purpose:
//   - orion: a Worker custom domain, owned by the Worker
//   - cam, hass, print: Cloudflare Tunnel CNAMEs, deleted by hand with the
//     tunnel at cutover
locals {
  // Flip once the imported records plan clean.
  public_ingress_enabled = false

  dns_records = {
    apex = {
      name    = local.domain
      type    = "A"
      content = "199.34.228.171"
    }
    www = {
      name    = "www.${local.domain}"
      type    = "CNAME"
      content = local.domain
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
      content = "v=spf1 include:_spf.google.com include:mailgun.org ~all"
    }
    apple_verification = {
      name    = local.domain
      type    = "TXT"
      content = "apple-domain-verification=Xk5LgQyYqBacTS0M"
    }
    dmarc = {
      name    = "_dmarc.${local.domain}"
      type    = "TXT"
      content = "v=DMARC1; p=none; pct=100; fo=1; ri=3600; rua=mailto:f45a103b@dmarc.mailgun.org,mailto:6cff95db@inbox.ondmarc.com; ruf=mailto:f45a103b@dmarc.mailgun.org,mailto:6cff95db@inbox.ondmarc.com;"
    }
    google_dkim = {
      name    = "google._domainkey.${local.domain}"
      type    = "TXT"
      content = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAotcq8hnTeHZifnWt8rBd7o4URjUU5n+ImutOVeMfDOpt0tWiOSQznvVh8MHPSERZOFQQAV8s3a/E4FBo/i2R10yBvfHoAc6IpdkMVv6gIDja+gRz4tQMveb/j9jmLM12c+zOP0rfefKvJxgYy2cLPI6WlKWxNYwg91Tpk6hu2spiswe8i5I0kkZSj/XxOj2c5XPHwlBRMCq8++noZPvbJ8sdc4SM0m3Q1h3ZR+z7AIn6r+eiklpDkvlIphroYwbI7BgOryjCLmc7IdetFFpubx8/ZEXQ+S6O1H3TNbAVT/PjRzOoPmXJntAG1OmngMpDB7Ywba95duBiQflBy6tiYwIDAQAB"
    }
  }

  // "<zone_id>/<record_id>" for every key in dns_records
  dns_record_ids = {
    apex               = "TODO"
    www                = "TODO"
    mx                 = "TODO"
    spf                = "TODO"
    apple_verification = "TODO"
    dmarc              = "TODO"
    google_dkim        = "TODO"
  }
}
