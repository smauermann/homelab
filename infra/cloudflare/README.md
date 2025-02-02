# Cloudflare Tunnel

## Prerequisites
A Cloudflare account, a domain, the domain set up in Cloudflare. An API token with the following permissions:
```
Account > Cloudflare Tunnel > Edit
Account > Access: Apps and Policies > Edit
Zone > DNS > Edit
Zone > Zone > Read
Zone > Zone Settings > Read
```

## Tunnel Config
Get the tunnel config by running `tofu output -raw tunnel_config | jq`.
