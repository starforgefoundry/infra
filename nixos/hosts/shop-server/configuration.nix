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

  # Move old recordings from SSD to HDD nightly at 1am
  systemd.services.migrate-recordings = {
    description = "Migrate old recordings from SSD to HDD";
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        let
          script = pkgs.writeShellScript "migrate-recordings" ''
            SRC_DIR="/mnt/nvr-ssd/frigate/recordings"
            DEST_DIR="/mnt/nvr-hdd/frigate/recordings"

            ${pkgs.findutils}/bin/find "$SRC_DIR" -type f -mmin +20160 -print0 | while IFS= read -r -d "" file; do
              rel_path="''${file#$SRC_DIR/}"
              dest_file="$DEST_DIR/$rel_path"
              dest_dir="$(${pkgs.coreutils}/bin/dirname "$dest_file")"
              ${pkgs.coreutils}/bin/mkdir -p "$dest_dir"
              ${pkgs.rsync}/bin/rsync -a --remove-source-files "$file" "$dest_file"
            done

            ${pkgs.findutils}/bin/find "$SRC_DIR" -type d -empty -delete
          '';
        in
        "${script}";
    };
  };

  systemd.timers.migrate-recordings = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 01:00:00";
      Persistent = true;
    };
  };
}
