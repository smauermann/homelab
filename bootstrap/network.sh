#!/usr/bin/env bash

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf

# Advertise routes of ciliums loadbalancer ip pool
# Subnet routes must be approved in the tailscale admin console https://login.tailscale.com/admin/machines
# --advertise-routes string: routes to advertise to other nodes (comma-separated, e.g. "10.0.0.0/8,192.168.0.0/24")
# sudo tailscale up --advertise-routes="192.168.178.195/32,192.168.178.196/32,192.168.178.197/32,192.168.178.198/32,192.168.178.199/32,192.168.178.200/32"
sudo tailscale up
