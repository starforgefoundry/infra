{
  ...
}:

{
  services.beszel.agent.enable = true;
  services.beszel.agent.environment = {
    "KEY" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBnpRjTrh0PBJNKpXL6Xao+a1n6rHxIZ/wIgxY0hJwhN";
  };

  # The hub runs on vps-server and dials agents over the tailnet
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 45876 ];
}
