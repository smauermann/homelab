# tunnel secret
resource "random_bytes" "this" {
  length = 64
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id = var.account_id
  name       = "Homelab Kubernetes Tunnel"
  secret     = random_bytes.this.base64
}

resource "cloudflare_record" "argocd-webhook" {
  zone_id = var.zone_id
  name    = "argocd-webhook"
  content = cloudflare_zero_trust_tunnel_cloudflared.this.cname
  type    = "CNAME"
  proxied = false
}

resource "cloudflare_record" "ingress" {
  zone_id = var.zone_id
  name    = "*"
  content = "100.70.249.33" # tailnet IP of the exposed ingress
  type    = "A"
  proxied = false
}
