terraform {
  # Credentials come from the environment (tofu/.env via mise) so they never
  # land in .terraform/ or plan files: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  backend "s3" {
    bucket = "infra-tofu-state"
    key    = "infra.tfstate"
    region = "auto"

    endpoints = {
      s3 = "https://58deea9a6c523e2f0bcea4d2bc0b81de.r2.cloudflarestorage.com"
    }

    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}
