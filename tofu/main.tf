locals {
  talos_version = "v1.8.3"
  talos_endpoint = "https://192.168.178.101:6443"
  cluster_name = "talos"
  cilium_values = file("${path.module}/../kubernetes/infrastructure/network/cilium/values.yaml")
}

resource "talos_machine_secrets" "this" {
  talos_version = local.talos_version
}

data "talos_image_factory_extensions_versions" "this" {
  talos_version = local.talos_version
  filters = {
    names = [
      "i915-ucode",
      "intel-ucode",
      "util-linux-tools",
      "iscsi-tools",
      "tailscale"
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode(
    {
      customization = {
        systemExtensions = {
          officialExtensions = data.talos_image_factory_extensions_versions.this.extensions_info.*.name
        }
      }
    }
  )
}

data "talos_image_factory_urls" "this" {
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
}

data "talos_machine_configuration" "this" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.talos_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  config_patches = [
    templatefile("${path.module}/config-patches/jerry.yaml", {image=data.talos_image_factory_urls.this.urls.installer}),
    file("${path.module}/config-patches/cluster.yaml"),
    templatefile("${path.module}/config-patches/cilium-install.yaml", {cilium_values=local.cilium_values})
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = ["192.168.178.101"]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = "192.168.178.101"
}
