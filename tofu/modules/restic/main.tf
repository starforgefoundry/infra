resource "cloudflare_r2_bucket" "volsync" {
  account_id = var.account_id
  name       = var.bucket_name
}

resource "cloudflare_account_token" "volsync" {
  account_id = var.account_id
  name       = "volsync restic"

  policies = [
    {
      effect = "allow"
      permission_groups = [
        { id = "2efd5506f9c8494dacb1fa10a3e7d5b6" }, # Workers R2 Storage Bucket Item Write
        { id = "6a018a9f2fc74eb6b293b0c548f38b39" }, # Workers R2 Storage Bucket Item Read
      ]
      resources = jsonencode({
        "com.cloudflare.edge.r2.bucket.${var.account_id}_default_${cloudflare_r2_bucket.volsync.name}" = "*"
      })
    }
  ]
}

resource "random_password" "restic" {
  length  = 64
  special = false
}

// R2's S3 credentials are derived from the API token: its id is the access key
// and the SHA-256 of its value is the secret.
resource "onepassword_item" "restic_r2" {
  vault    = var.vault_uuid
  title    = "restic-r2"
  category = "password"

  section_map = {
    "credentials" = {
      field_map = {
        "repository" = {
          type  = "STRING"
          value = "s3:https://${var.account_id}.r2.cloudflarestorage.com/${cloudflare_r2_bucket.volsync.name}"
        }
        "repo_password" = {
          type  = "CONCEALED"
          value = random_password.restic.result
        }
        "access_key_id" = {
          type  = "STRING"
          value = cloudflare_account_token.volsync.id
        }
        "secret_access_key" = {
          type  = "CONCEALED"
          value = sha256(cloudflare_account_token.volsync.value)
        }
      }
    }
  }
}
