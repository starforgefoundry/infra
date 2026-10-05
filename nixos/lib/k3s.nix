{ pkgs, config, ... }:

let
  # imageMaximumGCAge is a KubeletConfiguration-only field (no equivalent
  # --kubelet-arg flag), so it must be supplied via a config file.
  kubeletConfig = pkgs.writeText "k3s-kubelet-config.yaml" ''
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    imageMaximumGCAge: "168h"
    shutdownGracePeriod: "120s"
    shutdownGracePeriodCriticalPods: "60s"
  '';
in
{
  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = [
      "--disable=traefik"
      "--disable=local-storage"
      "--disable=metrics-server"
      "--disable=servicelb"
      "--disable-helm-controller"
      "--write-kubeconfig-mode=0640"
      "--write-kubeconfig-group=k3s"
      "--kube-apiserver-arg=feature-gates=ImageVolume=true"
      "--kubelet-arg=feature-gates=ImageVolume=true"
      "--kubelet-arg=config=${kubeletConfig}"
      # Quoted: systemd splits ExecStart on spaces, and k3s ignores every flag
      # after the first stray word.
      ''--etcd-snapshot-schedule-cron="0 */6 * * *"''
      "--etcd-snapshot-retention=14"
    ];
  };

  # CoreDNS copies the node's resolv.conf when it starts, so it only resolves
  # tailnet names if Tailscale DNS is already in place. Gives up after a minute
  # so a tailnet outage cannot hold the cluster down.
  systemd.services.k3s = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    serviceConfig.ExecStartPre = [
      "-${pkgs.coreutils}/bin/timeout 60 ${pkgs.bash}/bin/sh -c 'until ${pkgs.gnugrep}/bin/grep -q 100.100.100.100 /etc/resolv.conf; do sleep 1; done'"
    ];
  };

  services.rpcbind.enable = true;
  boot.supportedFilesystems = [ "nfs" ];

  services.logind.settings.Login.InhibitDelayMaxSec = 130;

  # expose k3s ports to tailscale0 interface for remote access
  # use k3s-multinode.nix for multi-node clusters, which exposes the same ports on the LAN interface
  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    6443 # kube-apiserver
    10250 # kubelet metrics
  ];

  users.groups.k3s = { };
  users.users.starforge.extraGroups = [ "k3s" ];

  environment.variables.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
  virtualisation.containerd.enable = true;

  environment.systemPackages = with pkgs; [
    fluxcd
    k9s
    nfs-utils
  ];
}
