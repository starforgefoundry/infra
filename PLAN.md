# Migration Plan: Docker Compose → Kubernetes + Flux

Moves this repo from Ansible-deployed Docker Compose on a single NixOS box to two
Flux-managed k3s clusters, drops Cloudflare Tunnels in favor of an Envoy dynamic
forward proxy on a VPS, and adds an infra-only OpenTofu configuration for
Cloudflare, Tailscale and Flux. Staff provisioning (Workspace, Ramp, Discord)
stays in `starforge/staff`.

`~/Developer/homelab` is the reference implementation. Where homelab already
solves a problem, this plan copies its structure rather than inventing a new one.

## Decisions already made

| Question         | Answer                                                              |
| ---------------- | ------------------------------------------------------------------- |
| Cluster names    | `shop` (local, at the foundry) and `vps` (remote entrypoint)        |
| NixOS host names | `shop-server` and `vps-server` (renamed from `starforge-*`)   |
| OpenTofu layout  | One root, one state, decomposed into `tofu/modules/*`               |
| OpenTofu scope   | Infra only; staff Tofu stays in `starforge/staff`                   |
| VPS              | New Contabo instance, managed by OpenTofu like homelab's `tau-ceti` |
| Bambuddy         | `hostNetwork` + node pin, not Cilium LB IPAM (see below)            |

---

## Target layout

```
infra/
├── kubernetes/
│   ├── clusters/
│   │   ├── base/            # shared Flux Kustomizations + HelmRelease patches
│   │   ├── shop/            # entrypoint Flux reconciles on shop-server
│   │   └── vps/             # entrypoint Flux reconciles on vps-server
│   ├── components/          # volsync, intel-gpu
│   └── apps/
│       ├── base/            # flux-system, secrets, networking, storage, operators
│       ├── shop/            # networking, smarthome, nvr, printing
│       └── vps/             # networking (envoy-dfp, bind9), monitoring
├── nixos/
│   ├── lib/                 # + k3s.nix, miroir.nix, beszel.nix from homelab
│   └── hosts/{shop-server,vps-server}/
├── tofu/
│   ├── config/              # single root module, single state
│   └── modules/             # contabo, dns, api-tokens, tailscale, flux-webhooks
├── apps/frigate-oauth/      # unchanged
├── mise.toml                # replaces justfile
└── .github/workflows/       # tofu.yml, images.yml
```

Deleted at the end: `compose/`, `ansible/`, `configs/traefik/`, `justfile`.
`configs/frigate.yml`, `configs/hass.yml` and `configs/mosquitto.conf` move into
the app directories as ConfigMaps.

---

## Networking design

### Ingress path, replacing Cloudflare Tunnels

Identical to homelab's `tau-ceti` → cluster chain:

1. `*.starforgefoundry.com` A record → the VPS public IP, DNS-only (grey cloud).
   TLS passthrough requires Cloudflare to stay out of the path.
2. The VPS runs `envoy-dfp`: a Gateway with a `TLS`/`Passthrough` listener on
   443 and a `TLSRoute` to a `DynamicResolver` Backend. It forwards by SNI and
   decrypts nothing.
3. The DFP pods resolve exclusively through an in-cluster `bind9` that is
   authoritative for `starforgefoundry.com`. Without that split-horizon view the
   resolver would follow the public wildcard straight back to itself.
4. bind9's zone is written by each cluster's `external-dns-bind` over RFC2136
   (TSIG), from `HTTPRoute` hostnames, with
   `--default-targets=<cluster>-ingress.<tailnet>.ts.net --force-default-targets`.
5. The target is a Tailscale `ProxyGroup` VIPService fronting the cluster's
   `envoy-ingress` Gateway. Traffic crosses the tailnet, never the open internet.
6. `envoy-ingress` on the owning cluster terminates TLS with a cert-manager
   wildcard cert and routes to the app.

The one deliberate simplification versus homelab: starforge has a single zone, so
there is **no Cloudflare `external-dns`**. Every route-derived record lives in
bind9's private view; every public record is written by OpenTofu. One writer per
view, no ownership contention.

### Certificates

- `cert-manager` in both clusters, DNS-01 against Cloudflare.
- One `Certificate` for `starforgefoundry.com` + `*.starforgefoundry.com`.
- `dns01RecursiveNameservers: 1.1.1.1:53` with `dns01RecursiveNameserversOnly`,
  because the split-horizon view holds no `_acme-challenge` records.

### Tailnet

- The `vps` and `shop` nodes join the starforge tailnet with
  `--advertise-tags=tag:<cluster>,tag:nixos`.
- The Tailscale operator runs in both clusters; `ProxyGroup` `<cluster>-ingress`
  exposes each Gateway as a tailnet service.
- Tailscale ACLs, tag owners and `autoApprovers.services` move into OpenTofu,
  mirroring `homelab/tofu/config/tailscale.tf`.

### Bambuddy: why `hostNetwork`, not Cilium

Bambuddy needs SSDP discovery on the printer VLAN and one IP per virtual printer.
Today `network_mode: host` gives the container the node's `printers` VLAN
interface, which NixOS already configures with `10.0.60.201` and `10.0.60.202`.

`hostNetwork: true` + `nodeSelector: kubernetes.io/hostname: shop-server` +
`strategy: Recreate` is a 1:1 match for that: the pod gets every node address,
including both printer-VLAN IPs, and broadcast/multicast work because it shares
the node's stack. Homelab already uses exactly this shape for `home-assistant`,
`matter-server` and `mosquitto`.

Cilium LB IPAM is the wrong tool here. It would mean swapping the CNI on both
clusters (k3s ships flannel; homelab keeps it), diverging from the reference
setup, and it still would not deliver SSDP broadcast onto VLAN 4 without
additional L2 announcement configuration — while `hostNetwork` needs none of it.
Revisit only if bambuddy ever has to run somewhere other than the node that owns
the printer VLAN.

### Open networking question: LAN hairpin

Once the tunnels are gone, a client on the shop LAN resolving
`cam.starforgefoundry.com` gets the VPS public IP: traffic leaves the building,
hits the VPS, and comes back over the tailnet. Camera streams make this expensive
(it is not a regression — Cloudflare Tunnel hairpins today — but it is worth
fixing).

Cheapest fix: a handful of local DNS overrides on the shop router pointing
`cam`/`hass`/`print` at the shop ingress address. No cluster change. Decide
before cutover.

---

## OpenTofu

New `infra/tofu/config`, one root module and one state, scoped to
infrastructure only. Staff provisioning (`googleworkspace`, `ramp`, `discord`,
`staff.json`, custom providers) stays in `starforge/staff` untouched.

| Module          | Contents                                                                                                    |
| --------------- | ----------------------------------------------------------------------------------------------------------- |
| `contabo`       | `contabo_instance.starforge_vps`, outputs the public IPv4 for `dns`                                         |
| `dns`           | `starforgefoundry.com` zone: wildcard → VPS, apex, `orion`, Workspace MX/SPF/DKIM/DMARC, static LAN records |
| `bind9-tsig`    | Random HMAC-SHA256 key for bind9 / external-dns, written to 1Password                                       |
| `api-tokens`    | Scoped Cloudflare account tokens for cert-manager and Pages, written back to 1Password                      |
| `tailscale`     | ACLs, tag owners, DNS preferences, `autoApprovers.services` for `shop-ingress` / `vps-ingress`              |
| `flux-webhooks` | Per-cluster `random_password` + GitHub repository webhook + 1Password item                                  |

State: Cloudflare R2, bucket `infra-tofu-state`, key `infra.tfstate`. Staff
manages no Cloudflare resources today, so nothing moves between states — every
infra resource is new or imported from the live account.

### Contabo VPS

Same shape as `homelab/tofu/config/contabo.tf`:

- Order the instance in the Contabo panel (public IPv4 required), then adopt it
  with an `import` block keyed on the instance ID. The provider's create path
  is not used.
- `contabo/contabo` provider, OAuth2 credentials (`client_id`, `client_secret`,
  `user`, `password`) read from a `contabo` section of the 1Password item the
  Tofu providers already use.
- `lifecycle.prevent_destroy = true` — destroying cancels the contract.
- `ignore_changes` on `image_id`, `ssh_keys`, `user_data`, `root_password`,
  `default_user` — changing any of them reinstalls the OS.
- The module outputs `ip_config[0].v4[0].ip`; `modules/dns` points the wildcard
  at it, so the IP is never hand-copied.

The OS is replaced by NixOS with `nixos-anywhere`, copying
`homelab/nixos/hosts/tau-ceti`:

- `disk-config.nix` (disko) + `hardware-configuration.nix` for the Contabo VM.
- `services.k3s.extraFlags`: `--node-ip=<public ip>` and
  `--node-external-ip=<public ip>`. Both are required — without `--node-ip`
  k3s detects dual-stack and drops the IPv4 external IP, and the Tailscale
  operator then has no static endpoint to advertise.
- Firewall: TCP 80/443 for `envoy-dfp`, and the UDP NodePort range that matches
  the `vps-static-endpoints` `ProxyClass` (`staticEndpoints.nodePort.ports`).
- `openssh` with password auth off, `fail2ban` on.

### Importing the zone

The riskiest step in the whole migration. `starforgefoundry.com` already carries
live mail routing. Before any apply:

1. Export every record: `cloudflare_dns_records` data source or the dashboard.
2. Write them into `modules/dns` verbatim, including MX, SPF, DKIM, DMARC and
   anything Google Workspace added.
3. `tofu import` each one, then `tofu plan` until it is **empty**.
4. Only then add the `*` wildcard record.

Explicit records beat the wildcard in Cloudflare's resolution order, so the
website and `orion` keep working once the wildcard lands.

---

## Storage

| Data                        | Today                       | After                                                               |
| --------------------------- | --------------------------- | ------------------------------------------------------------------- |
| Frigate recordings          | `/mnt/nvr-storage` mergerfs | Static hostPath PV (mergerfs + nightly migrate timer stay in NixOS) |
| Frigate DB                  | `/storage/frigate`          | `miroir` PVC                                                        |
| Home Assistant config       | `/storage/hass`             | `miroir` PVC + ConfigMap for `configuration.yaml`                   |
| Mosquitto, matter, bambuddy | `/storage/*`                | `miroir` PVCs                                                       |

`miroir` with 1 replica on each single-node cluster, exactly as homelab's
`eridani`/`stepien`. Needs `lib/miroir.nix` (`loop`, `dm_thin_pool` kernel
modules) and the `storage.miroir.home-operations.com/class: std` node label.

Backups: the `volsync` component from homelab with a single nightly restic
target, the `volsync` R2 bucket created by `modules/restic`. Mosquitto and
bind9 are not backed up.

### Moving data into PVCs

One repeatable recipe, used for every stateful app:

1. Stop the Docker service for that app.
2. Apply the app's manifests so the PVC is created and bound, with the workload
   scaled to 0.
3. Run a one-shot Job pinned to `shop-server` mounting both the hostPath
   (`/storage/<app>`) and the PVC, running `rsync -a`.
4. Scale the workload up, verify, then remove the compose service.

---

## App-by-app mapping

| Compose service         | Destination              | Notes                                                                                                                                                                                                                                                                                                                       |
| ----------------------- | ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `traefik`               | deleted                  | Replaced by `envoy-ingress` in both clusters                                                                                                                                                                                                                                                                                |
| `cloudflared`           | deleted                  | Replaced by `envoy-dfp` on the VPS                                                                                                                                                                                                                                                                                          |
| `frigate`               | `shop/nvr`               | Pod network with `hostPort` 8554/8555 (go2rtc RTSP/WebRTC on the existing candidate IPs) — `hostNetwork` would expose unauthenticated port 5000 on the LAN; Intel GPU via the `intel-gpu` component, 4Gi `emptyDir` at `/dev/shm`, 1Gi memory `emptyDir` at `/tmp/cache`, hostPath PV for `/media/frigate`                  |
| `oauth-middleware`      | `shop/nvr`               | `main.go` falls back to the request URI when `X-Forwarded-Uri` is absent (Envoy ext_authz sends the original path as the request path); wired via Envoy Gateway `SecurityPolicy.extAuth.http` with `headersToBackend: [x-forwarded-user, x-forwarded-groups]` — a direct equivalent of the Traefik `forwardauth` middleware |
| `homeassistant`         | `shop/smarthome`         | `hostNetwork` + node pin; `/dev/ttyUSB0` as a hostPath `CharDevice` (switch to a `/dev/serial/by-id/` path); `trusted_proxies` changes from `172.40.0.0/24` to the pod CIDR                                                                                                                                                 |
| `matter-server`         | `shop/smarthome`         | Copy homelab's manifest verbatim, adjusting `--primary-interface`                                                                                                                                                                                                                                                           |
| `mosquitto`             | `shop/smarthome`         | Copy homelab's manifest verbatim                                                                                                                                                                                                                                                                                            |
| `bambuddy`              | `shop/printing`          | `hostNetwork` + node pin + `Recreate`                                                                                                                                                                                                                                                                                       |
| `printer-subnet-router` | `shop-server` NixOS | `10.0.60.0/24` added to the node's `--advertise-routes`                                                                                                                                                                                                                                                                     |
| `bwees-subnet-router`   | `shop/networking`        | Userspace `tailscale` pod with a `miroir` PVC for state                                                                                                                                                                                                                                                                     |
| `beszel` (NixOS)        | `vps/monitoring` (hub)   | Agents stay as `lib/beszel.nix` on each node                                                                                                                                                                                                                                                                                |

### Subnet routers

`compose/misc.yml` runs two Tailscale containers advertising the same
`10.0.60.0/24`, one per tailnet (starforge and personal):

- The starforge-side advertisement folds into the node's
  `services.tailscale.extraSetFlags`, next to `10.0.10.0/24`.
- The personal tailnet keeps its own pod, `bwees-subnet-router`, since a NixOS
  host joins one tailnet.

---

## Secrets

Ansible + `op read` at deploy time is replaced by External Secrets, identical to
homelab:

- 1Password vault: `Starforge Deployment`.
- 1Password Connect in the `secrets` namespace, seeded once by the bootstrap task.
- `ClusterSecretStore` named `onepassword`.

Items to create:

| Item                 | Consumed by                                                |
| -------------------- | ---------------------------------------------------------- |
| `cf-cert-manager`    | cert-manager DNS-01                                        |
| `bind9-tsig`         | bind9 + every `external-dns-bind`                          |
| `tailscale-operator` | Tailscale operator OAuth client                            |
| `flux-webhooks`      | Flux `Receiver` per cluster (written by Tofu)              |
| `flux-github-status` | Flux GitHub commit-status Provider                         |
| `frigate`            | `FRIGATE_TAPO_PASSWORD`, `FRIGATE_TAPO_CLOUD_PASSWORD`     |
| `gauth`              | `GAUTH_CLIENT_ID`/`SECRET` for frigate-oauth and HA OpenID |
| `frigate-oauth`      | `AUTH_SECRET`                                              |
| `restic-*`           | volsync                                                    |

---

## Execution steps

Checked boxes are done. Everything through step 4.3 is additive: Docker keeps
serving traffic until step 6.

### 1. Repo scaffolding

- [x] 1.1 `kubernetes/` — clusters `shop` and `vps`, shared `apps/base`, the
      `volsync` (R2) and `intel-gpu` components, every app manifest.
- [x] 1.2 `nixos/lib/{k3s,miroir,beszel}.nix`; `hosts/vps-server`;
      `shop-server` gains k3s, miroir, `tag:shop`, the `10.0.60.0/24` route.
- [x] 1.3 `tofu/config` + `tofu/modules/{contabo,dns,api-tokens,restic,tailscale,flux-webhooks}`.
- [x] 1.4 `mise.toml` tasks: `bootstrap`, `cluster:*`, `nixos:*`,
      `migrate:pvc`, `tofu:dns-export`.
- [x] 1.5 `.github/workflows/tofu.yml`, manual trigger only.
- [x] 1.6 `apps/frigate-oauth/main.go` works behind Envoy ext_authz.
- [ ] 1.7 Commit and push. Flux reads from GitHub, so nothing below step 3.3
      works until this lands.

### 2. Secrets and credentials

All in the `Starforge Deployment` 1Password vault unless noted.

- [x] 2.1 `infra-tofu-credentials` with sections `cloudflare`, `github`, `contabo`,
      `tailscale` (fields in `tofu/README.md`).
- [x] 2.2 1Password Connect server for the vault, stored as
      `1password-connect` (`access_token`, `1password-credentials.json`).
- [x] 2.3 `tailscale-operator` (`client_id`, `client_secret`): Tofu `modules/tailscale`, created at 4.4.
- [x] 2.4 `bind9-tsig` (`password`, random): Tofu `modules/bind9-tsig`, created at 4.4.
- [x] 2.5 `flux-github-status` (`credential`, commit-status write on `infra`).
- [x] 2.6 Copy from the Ansible item `m5bkirljj5u3hx7cum5aza46py`:
  - `frigate` — `FRIGATE_TAPO_PASSWORD`, `FRIGATE_TAPO_CLOUD_PASSWORD`
  - `gauth` — `GAUTH_CLIENT_ID`, `GAUTH_CLIENT_SECRET`
  - `frigate-oauth` — `AUTH_SECRET`
- [x] 2.7 `tofu/.env`: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
      `OP_ACCOUNT`. GitHub repo secrets: the same AWS vars plus
      `OP_SERVICE_ACCOUNT_TOKEN`.

### 3. VPS cluster (`vps`)

- [x] 3.1 Order the Contabo VPS (`194.238.28.254`, St. Louis).
- [x] 3.2 `nixos-anywhere` onto the VPS; node has ExternalIP `194.238.28.254`.
- [x] 3.3 VPS joined the tailnet as a regular device; `tag:vps` does not exist until 4.4.
- [x] 3.4 `mise run bootstrap vps-server vps`.
- [x] 3.5 Verify bind9, envoy-dfp, envoy-ingress and `vps-ingress` are up.

### 4. OpenTofu

- [x] 4.1 Put the Contabo instance ID in `tofu/config/imports.tf`.
- [x] 4.2 `mise run tofu:dns-export`; fill `dns_record_ids` in
      `tofu/config/dns.tf` and add any record missing from `dns_records`
      (Mailgun, static LAN).
- [x] 4.3 `tofu plan` until the only changes are new resources (tokens, R2
      bucket, 1Password items, webhooks). Read the Tailscale ACL diff: the module
      replaces the current policy. **Do not apply a plan that modifies or
      destroys an imported DNS record.**
- [x] 4.4 `tofu apply`, then tag the VPS: `sudo tailscale up --advertise-tags=tag:vps,tag:nixos`.
- [x] 4.5 Set `public_ingress_enabled = true` in `dns.tf`, apply, and test the
      DFP end to end with a throwaway route.
- [x] 4.6 Restore the push trigger in `tofu.yml`.

### 5. Shop cluster (`shop`)

- [x] 5.1 `mise run nixos:switch shop-server`. k3s enables the system
      containerd, which may restart the Docker containers.
- [x] 5.2 `tailscale up --advertise-tags=tag:shop,tag:nixos` on the server.
- [ ] 5.3 `mise run bootstrap shop-server shop`.
- [ ] 5.4 Confirm `shop-ingress` is reachable through the VPS DFP.

### 6. App migration

Per app: `docker compose stop <svc>`, suspend the app's Flux Kustomization,
`mise run migrate:pvc <ns> <claim> <host dir>`, resume, verify. Routes stay on
Traefik until each app is verified, then flip.

- [ ] 6.1 `mosquitto` — `smarthome mosquitto-data /storage/mosquitto/data`.
- [ ] 6.2 `matter-server` — `smarthome matter-server-data /storage/matter`.
- [ ] 6.3 `home-assistant` — `smarthome home-assistant-config /storage/hass`.
      Switch the dongle to its `/dev/serial/by-id/` path first. Verify Zigbee and
      OpenID login. Repoint the Frigate integration to
      `frigate.nvr.svc.cluster.local:5000`.
- [ ] 6.4 `bambuddy` — `printing bambuddy-data /storage/bambuddy` (holds
      `data/` and `logs/`). Verify SSDP discovery from a slicer on the shop LAN.
- [ ] 6.5 `frigate` + `frigate-oauth` — `nvr frigate-db /storage/frigate`.
      Verify GPU detection, recordings under `/mnt/nvr-storage`, WebRTC playback,
      the Google login flow.
- [ ] 6.6 `bwees-subnet-router` —
      `networking bwees-subnet-router-state /storage/bwees-sr`; stop
      `printer-subnet-router`.
- [ ] 6.7 beszel hub — move `/var/lib/beszel-hub` from `shop-server` into
      `beszel-data` on the VPS, then drop `services.beszel.hub` from the server.

### 7. Cutover

- [ ] 7.1 Delete the Cloudflare Tunnel and its `cam`/`hass`/`print` CNAMEs in
      the dashboard (neither is in Tofu).
- [ ] 7.2 Stop and remove `traefik` and `cloudflared`.
- [ ] 7.3 Add shop-LAN DNS overrides if the hairpin decision lands that way.

### 8. Cleanup

- [ ] 8.1 Delete `compose/`, `ansible/`, `configs/`, `justfile`,
      `.github/workflows/deploy-infra.yml`.
- [ ] 8.2 Remove `lib/docker.nix` from `shop-server`; drop `ansible` and
      `just` from `mise.toml`.
- [ ] 8.3 Add `.github/workflows/images.yml` for `apps/frigate-oauth`.
- [x] 8.4 Adopt homelab's `renovate.json` (home-operations presets, fluxcd
      grouping).
- [ ] 8.5 Rewrite `README.md` on homelab's structure.

---

## Rollback

Every phase before 5 is additive — the Docker stack keeps serving traffic through
Traefik and Cloudflare Tunnel the whole time. Rollback for phases 2–4 is: scale
the Flux app to 0, `docker compose up` the service again, repoint the Traefik
route.

Phase 5 is the point of no return for ingress. Keep the tunnel credentials and
`compose/backend.yml` in git history until the DFP has run clean for a week.

Phase 1 is the point of no return for DNS. The empty-plan gate is what protects
mail delivery; do not skip it.

---

## Open items

1. **LAN hairpin** — router-level DNS overrides, or accept the round trip.
2. **Frigate auth, longer term** — Envoy Gateway's native OIDC `SecurityPolicy`
   with `claimToHeaders` could retire `apps/frigate-oauth` entirely. Worth a
   spike after the migration, not during it.
3. **Monitoring scope** — whether the `vps` cluster picks up Gatus for starforge
   endpoints, or homelab's existing Gatus keeps covering them.
