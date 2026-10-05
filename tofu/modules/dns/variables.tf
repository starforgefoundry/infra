variable "zone_id" {
  type = string
}

variable "public_ingress_ipv4" {
  description = "Address the wildcard points at. Null leaves the wildcard out."
  type        = string
  default     = null
}

variable "redirects" {
  description = "Hostnames that 301 to another URL, keeping the query string"
  type = map(object({
    host   = string
    target = string
  }))
  default = {}
}
