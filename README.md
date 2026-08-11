# zrr-compose

Git is the only source of truth for the home Docker deployment. Komodo applies
the repository configuration, records audit history, and runs ordered backup,
deployment, and verification Procedures; runtime edits in the Komodo UI are
disabled after bootstrap.

## Layout

- `deployments/home/<stack>/compose.yml`: nine stable Compose projects and 35 services.
- `komodo/resources/*.toml`: Server, Stack, Action, Procedure, Alerter, and permission resources.
- `komodo/core`: pinned Komodo Core 2.2.0, MongoDB, encrypted backup, and restore-drill assets.
- `komodo/periphery`: pinned systemd Periphery 2.2.0 configuration and installer.
- `scripts`: repository contracts and Compose validation.
- `renovate.json5`: reviewed image-update policy.

Run the same entry point locally and in CI:

```sh
just check
```

Compose parsing needs Docker Compose v2. The nine production Stack files are
also parsed against the real Docker engine before rollout.

See [the Komodo operation guide](docs/operations/komodo.md) for bootstrap,
cutover, rollback, disaster recovery, and acceptance checks. The
[domain and certificate guide](docs/operations/domains.md) defines the Caddy
wildcard, canonical names, Cloudflare boundary, and two-phase alias retirement.
