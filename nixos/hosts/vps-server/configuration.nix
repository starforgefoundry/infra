{
  ...
}:

let
  addresses = import ./addresses.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../lib/base-packages.nix
    ../../lib/beszel.nix
    ../../lib/starforge.nix
    ../../lib/garbage-collect.nix
    ../../lib/tailscale.nix
    ../../lib/k3s.nix
    ../../lib/miroir.nix
  ];

  system.stateVersion = "26.05";

  # Networking/Clock
  networking.hostName = "vps-server";
  time.timeZone = "America/Chicago";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  services.tailscale.extraUpFlags = [
    "--advertise-tags=tag:vps,tag:nixos"
  ];

  services.tailscale.extraSetFlags = [
    "--accept-routes"
  ];

  services.k3s.extraFlags = [
    # Expose the public IP as the node's ExternalIP so the Tailscale operator can
    # advertise it as a static endpoint for direct ingress connections.
    # --node-ip must be pinned: otherwise k3s auto-detects a dual-stack node and
    # silently drops the IPv4-only --node-external-ip, leaving no ExternalIP.
    "--node-ip=${addresses.ipv4}"
    "--node-external-ip=${addresses.ipv4}"
  ];

  # envoy-dfp claims the public IP as a Service externalIP and forward-proxies
  # *.starforgefoundry.com to whichever cluster owns the hostname.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Allow inbound UDP to the Tailscale ingress static-endpoint NodePorts on the
  # public interface. Must match spec.staticEndpoints.nodePort.ports of the
  # `vps-static-endpoints` ProxyClass.
  networking.firewall.allowedUDPPortRanges = [
    {
      from = 31670;
      to = 31690;
    }
  ];

  services.fail2ban.enable = true;
}
