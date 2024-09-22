#!/usr/bin/env bash
set -ex

./dependencies.sh
./network.sh
./k3s.sh
./cilium.sh
./onepassword.sh
./argocd.sh
