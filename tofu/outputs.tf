output "schematic_id" {
  value = talos_image_factory_schematic.this.id
}

output "talosconfig" {
  value = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "disk_image" {
  value = data.talos_image_factory_urls.this.urls.installer
}
