variable "zone_id" {
  type = string
}

variable "records" {
  description = "Records that already exist in the zone, keyed by a stable name"
  type = map(object({
    name     = string
    type     = string
    content  = string
    ttl      = optional(number, 1)
    proxied  = optional(bool, false)
    priority = optional(number)
  }))
}

variable "public_ingress_ipv4" {
  description = "Address the wildcard points at. Null leaves the wildcard out."
  type        = string
  default     = null
}
