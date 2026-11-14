{
  pkgs,
  ...
}:

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

  system.stateVersion = "25.11";

  # Networking/Clock
  networking.hostName = "shop-server";
  # The SPCC SSD on ata1 hangs and drops off the bus. Keep the kernel off it.
  boot.kernelParams = [ "libata.force=1:disable" ];

  # Hangs have left no logs because the journal lives on the disk that may be
  # vanishing. Panic instead so the kernel log lands in EFI pstore, then reboot.
  # Read it after a crash from /var/lib/systemd/pstore.
  boot.kernel.sysctl = {
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
    "kernel.softlockup_panic" = 1;
    "kernel.hardlockup_panic" = 1;
    "kernel.hung_task_panic" = 1;
    # Above the default 120s so slow recording-disk I/O alone does not panic.
    "kernel.hung_task_timeout_secs" = 300;
  };
  systemd.settings.Manager.RuntimeWatchdogSec = "30s";

  time.timeZone = "America/Chicago";

  networking.firewall.enable = false;

  # Bambuddy's virtual printers each need their own IP on the printer VLAN, and
  # SSDP discovery only reaches slicers that share the broadcast domain.
  # VLAN 4 carries 10.0.60.0/24 — the tag does not track the subnet here.
  networking.vlans.printers = {
    id = 4;
    interface = "enp0s31f6";
  };

  networking.interfaces.printers = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "10.0.60.201";
        prefixLength = 24;
      }
      {
        address = "10.0.60.202";
        prefixLength = 24;
      }
    ];
  };

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  services.tailscale.ip = "100.121.137.68";
  services.tailscale.extraUpFlags = [
    "--advertise-tags=tag:shop,tag:nixos"
  ];
  services.tailscale.extraSetFlags = [
    "--advertise-exit-node"
    "--advertise-routes=10.0.10.0/24,10.0.60.0/24"
  ];

  # The SPCC SSD keeps dropping off the bus, so recordings live on the HDD only.
  fileSystems."/mnt/nvr-storage" = {
    device = "/mnt/nvr-hdd";
    fsType = "none";
    options = [ "bind" ];
  };
}
