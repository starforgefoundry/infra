variable "zone_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "dmarc_report_address" {
  description = "The rua address Cloudflare DMARC Management adds when it is enabled"
  type        = string
}

variable "spf_includes" {
  description = "SPF domains allowed to send as the root domain"
  type        = list(string)
}
