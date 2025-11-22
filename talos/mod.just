set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

talos_dir := justfile_dir() + '/talos'
controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`

[private]
default:
  just -l talos

[doc('Apply Talos config to a node')]
apply node *args:
  just talos render-config "{{ node }}" | talosctl -n "{{ node }}" apply-config -f /dev/stdin {{ args }} 

[doc('Download Talos machine image')]
download-image version:
  SCHEMATIC_ID=$(just talos get-schematic); \
  gum spin --title "Downloading Talos {{ version }} $SCHEMATIC_ID ..." -- \
  curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
    -o "{{ talos_dir }}/talos-{{ version }}-$SCHEMATIC_ID.iso" \
    "https://factory.talos.dev/image/$SCHEMATIC_ID/{{ version }}/metal-amd64.iso"; \
  just log info "Download completed"

[doc('Generate schematic ID from Talos schematic')]
get-schematic:
  curl -sX POST --data-binary "@{{ talos_dir }}/schematic.yaml" "https://factory.talos.dev/schematics" | jq -r '.id'

[doc('Reboot a node')]
reboot node:
  gum confirm "Reboot node {{ node }}?" --default="No" && \
    talosctl -n {{ node }} reboot -m powercycle || exit 0

[doc('Render Talos config for a node')]
render-config node:
  SCHEMATIC=$(just talos get-schematic); \
    talosctl machineconfig patch <(just template "{{ talos_dir }}/base.yaml") \
    -p @<(just template "{{ talos_dir }}/patches/{{ node }}.yaml") |\
    sed -e "s|\$SCHEMATIC|$SCHEMATIC|g"

[doc('Reset a node')]
reset node *args:
  gum confirm "Reset node {{ node }}?" --default="No" && \
    talosctl -n "{{ node }}" reset --wipe-mode all --graceful=false {{ args }} || exit 0

[doc('Shutdown a node')]
shutdown node *args:
  gum confirm "Shutdown node {{ node }}?" --default="No" && \
    talosctl -n "{{ node }}" shutdown --force {{ args }} || exit 0

[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
  talosctl -n "{{ controller }}" upgrade-k8s --to {{ version }}

[doc('Upgrade Talos version on a node')]
upgrade node *args:
  talosctl -n "{{ node }}" upgrade -i "$(just talos machine-image)" -m powercycle --timeout=10m {{ args }}

[private]
machine-image:
  cat "{{ talos_dir }}/base.yaml" | yq -e 'select(.machine) | .machine.install.image'
