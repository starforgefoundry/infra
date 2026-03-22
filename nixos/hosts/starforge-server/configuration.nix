{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../lib/base-packages.nix
    ../../lib/bwees.nix
    ../../lib/docker.nix
    ../../lib/garbage-collect.nix
    ../../lib/tailscale.nix
  ];

  system.stateVersion = "25.11";

  # Networking/Clock
  networking.hostName = "starforge-server";
  time.timeZone = "America/New_York";

  # Prefer IPv4 over IPv6 due to IPv6 issues with ISP
  networking.enableIPv6 = false;

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  services.tailscale.ip = "100.93.153.81";
  services.tailscale.extraSetFlags = [
    "--advertise-exit-node"
  ];

  # mergerfs
  environment.systemPackages = with pkgs; [
    mergerfs
  ];

  fileSystems."/mnt/nvr-storage" = {
    fsType = "fuse.mergerfs";
    device = "/mnt/nvr-ssd:/mnt/nvr-hdd";
    options = [
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=ff"
      "moveonenospc=true"
    ];
  };
}
