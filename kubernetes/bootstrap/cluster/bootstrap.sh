#!/usr/bin/env bash
set -ex

cd k3s && ./install.sh && cd ..
cd cilium && ./install.sh && cd ..
cd argocd && ./install.sh && cd ..
