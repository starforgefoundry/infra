resource "random_bytes" "tsig" {
  length = 32
}

resource "onepassword_item" "tsig" {
  vault    = var.vault_uuid
  title    = "bind9-tsig"
  category = "password"
  password = random_bytes.tsig.base64
}
