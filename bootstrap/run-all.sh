#!/usr/bin/env bash
set -ex

./dependencies.sh
./k3s.sh
./cilium.sh
./argocd.sh
