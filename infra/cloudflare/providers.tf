terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.7.1"
    }
  }
  backend "s3" {
    bucket = "homelab-tofu-state"
    key    = "cloudflare/terraform.tfstate"

    region                      = "auto"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }

}


provider "cloudflare" {}
