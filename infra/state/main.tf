resource "cloudflare_r2_bucket" "this" {
  account_id = var.account_id
  name       = "homelab-tofu-state"
  location   = "WEUR"
}
