#!/usr/bin/env bash

sudo ip link delete cilium_host
sudo ip link delete cilium_net
sudo ip link delete cilium_vxlan

rm /etc/cni/net.d

