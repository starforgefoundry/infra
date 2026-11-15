variable "zone_id" {
  type = string
}

variable "domain" {
  type = string
}

variable "dkim_public_key" {
  description = "The p= value from the Resend dashboard's DKIM record"
  type        = string
}
