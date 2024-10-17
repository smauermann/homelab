#!/usr/bin/env bash

# allow the current user to use sudo w/o password
echo "$USER ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$USER
