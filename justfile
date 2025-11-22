#!/usr/bin/env -S just --justfile

# required for modules to work
set unstable := true

set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

mod bootstrap "bootstrap"
mod kube "kubernetes"
mod talos "talos"

[private]
default:
  just -l

[private]
log lvl msg *args:
  gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
template file *args:
  op inject -i "{{ file }}"
