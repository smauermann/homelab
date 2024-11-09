terraform {
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.6.1"
    }
  }
  backend "s3" {
    bucket = "costanza-cloud-tofu-state-homelab"
    key    = "talos/terraform.tfstate"
  }
}

provider "talos" {}
