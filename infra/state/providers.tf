terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.7.0"
    }
  }
}

provider "cloudflare" {}
