This repository contains all of Starforge Makerspace's infrastructure defined in Kubernetes and OpenTofu declarations. 

There are 2 machines used for hosting services:

- Shop: On-premise server running Orion, Bambuddy, and any other services that are required to be local
- VPS: Server on Contabo that hosts Orion and the public Wiki.

Public traffic arrives on a static opwan address, carried over a WireGuard tunnel into the shop's `envoy-dfp`, which forward-proxies by SNI over Tailscale to whichever cluster owns the hostname.

For staff onboarding OpenTofu, see https://github.com/starforgefoundry/staff
