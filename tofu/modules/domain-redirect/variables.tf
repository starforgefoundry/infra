variable "domain" {
  description = "Cloudflare zone whose every host redirects to target_origin"
  type        = string
}

variable "target_origin" {
  description = "Scheme and host to redirect to, e.g. https://example.com"
  type        = string
}

variable "status_code" {
  description = "Use 302 until the redirect is permanent so browsers do not cache it"
  type        = number
  default     = 302
}
