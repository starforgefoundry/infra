resource "contabo_instance" "starforge_vps" {
  display_name = "vps-server"

  lifecycle {
    // Destroying cancels the Contabo contract.
    prevent_destroy = true

    // Changing any of these reinstalls the OS.
    ignore_changes = [
      image_id,
      ssh_keys,
      user_data,
      root_password,
      default_user,
    ]
  }
}
