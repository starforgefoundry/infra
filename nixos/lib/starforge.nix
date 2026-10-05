{
  config,
  lib,
  ...
}:

{
  users.users.starforge = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJr7fOsF74yPo/dhdorxFhgnCURWPVDkIjeRz2md0Jzq" # bwees ssh key
    ];
  };

  users.users.root.openssh.authorizedKeys.keys = lib.concatLists [
    config.users.users.starforge.openssh.authorizedKeys.keys
  ];

  security.sudo.extraRules = [
    {
      users = [ "starforge" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
