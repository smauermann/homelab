# tunnel secret
resource "random_bytes" "tunnel_secret" {
  length = 64
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "this" {
  account_id    = var.account_id
  name          = "Homelab Kubernetes Tunnel"
  config_src    = "local"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

resource "cloudflare_dns_record" "argocd-webhook" {
  zone_id = var.zone_id
  name    = "argocd-webhook.${var.domain}"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.this.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}
