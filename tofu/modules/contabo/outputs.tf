output "public_ipv4" {
  value = contabo_instance.starforge_vps.ip_config[0].v4[0].ip
}
