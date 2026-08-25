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
      "docker"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJr7fOsF74yPo/dhdorxFhgnCURWPVDkIjeRz2md0Jzq" # bwees ssh key
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJWZcdaxk7yJsmRDh/DBUt6HEJsaaHzhjfMNxVwCZ0Gh" # gh actions deploy key
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
