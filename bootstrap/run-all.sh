#!/usr/bin/env bash
set -ex

./network.sh
./dependencies.sh
./k3s.sh
./cilium.sh
./onepassword.sh
./argocd.sh
