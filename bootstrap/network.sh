#!/usr/bin/env bash

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# add the static route to your linux machine
cat <<EOF
Add the static route for your loadbalancer IPs to your linux gateway. The file is called /etc/network/interfaces, below is an example.
After adding the route, restart the network stack via `sudo systemctl restart networking`.

Don't forget to add a static route to your router as well!
'''
# The primary network interface
allow-hotplug wlp0s20f3
iface wlp0s20f3 inet dhcp
        wpa-ssid Wifi
        wpa-psk  123456
        # add this route here to make it permanent
        up ip route add 192.168.192.0/24 via 192.168.178.100
'''
EOF

# start tailscale
sudo tailscale up --accept-routes
