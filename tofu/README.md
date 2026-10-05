# Tofu

Infrastructure outside the clusters: the Contabo VPS, the `starforgefoundry.com`
zone, scoped Cloudflare tokens, the R2 backup bucket, Tailscale policy and the
Flux webhooks. Staff provisioning lives in `starforge/staff`.

State is `infra.tfstate` in the `infra-tofu-state` R2 bucket. `tofu/.env`
(loaded by mise) holds `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and
`OP_ACCOUNT` (1Password desktop app). CI uses
`OP_SERVICE_ACCOUNT_TOKEN` instead of `OP_ACCOUNT`.

## Required Credentials

Item `infra-tofu-credentials` in the `Starforge Deployment` 1Password vault:

| Section      | Fields                                     | Permissions                                                              |
| ------------ | ------------------------------------------ | ------------------------------------------------------------------------ |
| `cloudflare` | `api_token`                                | Account: API Tokens Edit, Workers R2 Storage Edit; zone: Zone Read, DNS Edit |
| `github`     | `token`                                    | `starforgefoundry/infra`: Webhooks read/write                            |
| `contabo`    | `client_id`, `client_secret`, `username`, `password` | Contabo API                                                    |
| `tailscale`  | `client_id`, `client_secret`               | OAuth client, all scopes                                                 |

The 1Password service account needs read/write on `Starforge Deployment`.
