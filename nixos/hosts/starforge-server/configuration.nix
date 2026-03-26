{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
    ../../lib/base-packages.nix
    ../../lib/starforge.nix
    ../../lib/docker.nix
    ../../lib/garbage-collect.nix
    ../../lib/tailscale.nix
  ];

  system.stateVersion = "25.11";

  # Networking/Clock
  networking.hostName = "starforge-server";
  time.timeZone = "America/Chicago";

  networking.firewall.enable = false;

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

  # Move old recordings from SSD to HDD nightly at 1am
  systemd.services.migrate-recordings = {
    description = "Migrate old recordings from SSD to HDD";
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        let
          script = pkgs.writeShellScript "migrate-recordings" ''
            SRC_DIR="/mnt/nvr-ssd/recordings"
            DEST_DIR="/mnt/nvr-hdd/recordings"

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
