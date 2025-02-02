output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.this.id
}

output "tunnel_config" {
  value = tostring(jsonencode({
    AccountTag   = cloudflare_zero_trust_tunnel_cloudflared.this.account_id
    TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.this.id
    TunnelSecret = cloudflare_zero_trust_tunnel_cloudflared.this.tunnel_secret
  }))
  sensitive = true
}
