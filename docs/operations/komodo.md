# Komodo 2.2 GitOps operation guide

This guide owns the bootstrap and migration procedure for the home Docker
deployment. It deliberately separates the control plane from the workload
plane:

| Plane | Location | Ownership |
|---|---|---|
| Komodo Core and MongoDB | Incus `komodo-core`, `10.0.0.13:9120` | Never managed by Komodo |
| Komodo Periphery and 35 services | Incus `docker`, `10.0.0.5` | Periphery connects outbound over LAN |
| Public Core route | `komodo.zrr.dev` | Cloudflare Tunnel direct to Core, never Caddy |

The target service projects are:

| Stack | Services |
|---|---|
| `home-edge` | `caddy` |
| `home-control` | `spark`, `homepage`, `dozzle` |
| `home-immich` | `immich-db`, `immich-redis`, `immich-server`, `immich-machine-learning` |
| `home-ai` | `new-api-db`, `new-api`, `lobe-chat-db`, `lobe-chat`, `portkeyai` |
| `home-automation` | `n8n-db`, `n8n` |
| `home-media` | `alist`, `aria2`, `ariang`, `jellyfin`, `jellyseerr`, `sonarr`, `radarr`, `prowlarr` |
| `home-tools` | `vaultwarden`, `wallos`, `memos`, `it-tools`, `searxng`, `miniflux-db`, `miniflux`, `gitea-db` |
| `home-monitor` | `speedtest`, `speedtest-tracker`, `scrutiny` |
| `home-backup` | `restic` |

## Hard gates

Stop before creating or starting `komodo-core` unless all of these are true:

1. `10.0.0.13` has no ICMP, ARP, duplicate-address, or port conflict.
2. The iKuai DHCP configuration has a recorded MAC reservation for
   `10.0.0.13`, outside the dynamic allocation pool or explicitly excluded
   from it.
3. The frozen runtime inventory, logical backups, Restic snapshot, Compose
   hash, and encrypted pre-rewrite Git bundle have been read back.
4. Rewritten `main` and `v1` pass full-history Gitleaks and are published before
   any deployment clone is created. Old clones must never push again.
5. The migration PR is merged into the rewritten `main`.
6. Every existing public hostname has a valid Cloudflare edge certificate.
   The `*.home.sixbones.dev` names are deeper than Universal SSL's full-zone
   coverage and Cloudflare Tunnel hostnames are excluded from Total TLS. Use an
   Advanced/Custom certificate covering `*.home.sixbones.dev`, or migrate those
   routes to first-level names, before cutover; do not accept TLS handshake
   failure as an application result.

Do not move `/root/zrr-compose/volumes`, `/media/immich`, or
`/etc/zrr-compose/env`. Do not delete a volume during cutover or rollback.

## Provision Core

The Incus `default`, `container`, and `docker` profiles are required. `default`
provides the bridged `br0` NIC, so the IP is assigned by the external DHCP
server rather than Incus. Choose and collision-check a locally administered
MAC, reserve it in iKuai, then create the stopped instance:

```sh
KOMODO_MAC=REPLACE_WITH_RESERVED_MAC
test -n "$KOMODO_MAC"
test -z "$(incus list komodo-core --format csv -c n)"

incus init images:debian/13 komodo-core \
  --profile default --profile container --profile docker
incus config set komodo-core \
  limits.cpu=2 \
  limits.memory=4GiB \
  security.protection.delete=true \
  snapshots.schedule='0 3 * * *' \
  snapshots.expiry=7d \
  snapshots.schedule.stopped=false
incus config device override komodo-core root size=24GiB
incus config device override komodo-core eth0 hwaddr="$KOMODO_MAC"
```

Read back the expanded configuration before the first start. Start only after
the DHCP reservation is visible, then prove the guest received exactly
`10.0.0.13`. Install Docker Engine with Compose v2 and Restic in the guest.

Copy `komodo/core/compose.yml` to `/opt/komodo/compose.yml`. Create each bind
directory with root ownership and mode `0700`:

```text
/var/lib/komodo/mongo-data
/var/lib/komodo/mongo-config
/var/lib/komodo/keys
/var/lib/komodo/backups
/var/lib/komodo/syncs
/var/lib/komodo/repo-cache
/var/lib/komodo/action-cache
```

Copy `core.env.example` to `/etc/komodo/core.env`, replace every placeholder
with independent random values, and set `root:root 0600`. During only the
bootstrap window set `KOMODO_UI_WRITE_DISABLED=false`. Start Core with:

```sh
docker compose --file /opt/komodo/compose.yml config --quiet
docker compose --file /opt/komodo/compose.yml pull
docker compose --file /opt/komodo/compose.yml up --detach
```

Both images are fixed by tag and digest and carry `komodo.skip`; the Compose
project contains no Periphery. Verify Mongo is healthy, Core is reachable on
LAN port 9120, and no Mongo port is published.

## Publish Core without Caddy

Add a Cloudflare Tunnel public hostname that proxies
`komodo.zrr.dev` directly to `http://10.0.0.13:9120`.

Create two Access application paths:

- `komodo.zrr.dev/*`: the existing owner identity plus MFA allow policy.
- `komodo.zrr.dev/listener/*`: a more-specific Bypass policy and no broader
  path. Bypass does not provide Access enforcement or Access logging; Komodo's
  `KOMODO_WEBHOOK_SECRET` must verify the GitHub HMAC.

Validate the precedence from LAN and a public resolver. The UI path must return
the Access login/redirect to an unauthenticated client. A listener request
without a valid HMAC must reach Komodo but be rejected. See Cloudflare's
[application path precedence](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/app-paths/)
and [Bypass policy warning](https://developers.cloudflare.com/cloudflare-one/access-controls/policies/common-policies/).
Cloudflare documents the [Universal SSL depth limit](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/)
and the [Total TLS exclusion for Tunnel hostnames](https://developers.cloudflare.com/ssl/edge-certificates/additional-options/total-tls/).

## Bootstrap declarative resources

1. Sign in as the initial super-admin through Access.
2. Manually create the one `home-gitops` Resource Sync using
   `komodo/bootstrap-resource-sync.toml` and run it once.
3. Confirm the sync owns one outbound Server, nine Stacks, two operational
   Actions, two Procedures, the disabled Alerter placeholder, and the
   `home-observers` group.
4. Change `/etc/komodo/core.env` to `KOMODO_UI_WRITE_DISABLED=true` and recreate
   only the Core container. Confirm UI resource writes are refused.
5. Remove `KOMODO_INIT_ADMIN_PASSWORD` from the env file after the initial user
   is persisted, then recreate Core and confirm login still works.

The `Backup Core Database` Procedure runs daily at 01:00 Asia/Shanghai and
retains the built-in default of 14 local backups. Komodo backups are not
encrypted. Install `komodo/core/bin/restic-backup.sh` as
`/usr/local/sbin/komodo-restic-backup`, install the supplied systemd unit and
timer, and place independent R2 credentials in `/etc/komodo/restic.env` with
mode `0600`. The timer uploads at 02:15 only when a fresh Core backup exists.
The encrypted snapshot contains the dated database dump, Core/Periphery
communication keys, the root-only Core environment, and the pinned Compose
file; it does not copy a live MongoDB data directory.

Before enabling the timer, run `komodo/core/bin/verify-restore.sh` on the Core
host. It restores the latest backup into a fresh, isolated MongoDB container,
requires at least one restored collection, then removes only its exact drill
container and network. Record the backup folder and collection count.

## Connect the workload Server

After the sync creates `home-docker`, generate a one-time onboarding key for
that Server. On `10.0.0.5`, use a fresh clone of rewritten `main` and run:

```sh
install -m 0600 komodo/periphery/periphery.env.example /etc/komodo/periphery.env
# Replace REPLACE_ON_HOST without printing the key.
komodo/periphery/install.sh
systemctl start periphery.service
```

The installer verifies the official v2.2.0 x86_64 binary SHA-256 before
installing it. Periphery connects to `ws://10.0.0.13:9120` over LAN as
`home-docker`; it must not traverse Cloudflare Access. After the Server is
connected, remove the onboarding key from `/etc/komodo/periphery.env` and
restart Periphery.

Read back these security properties:

- inbound port 8120 is not listening;
- `disable_container_terminals=true`;
- server terminal remains enabled only for the two fixed audit/verification
  Actions and super-admin recovery;
- `home-observers` has `Read + Logs` and no Inspect, Write, or Terminal grant.

## GitHub trigger

Create one GitHub push webhook for:

```text
https://komodo.zrr.dev/listener/github/procedure/home-gitops-apply/main
```

Use `application/json`, the same high-entropy HMAC secret as Core, and only the
push event. Resource Sync and individual Stack webhooks stay disabled. A main
push therefore starts only `home-gitops-apply`; Git merge remains the sole
runtime change path.

## Cut over the nine Stacks

Create the external network once and verify it is initially empty:

```sh
docker network inspect edge >/dev/null 2>&1 || docker network create edge
docker network inspect edge --format '{{.Name}} {{.Driver}} {{len .Containers}}'
```

Before `home-monitor`, the Incus host must expose the real NVMe device to the
`docker` instance. Verify `/dev/nvme0` exists on the host, is absent in the
guest, and that no device named `nvme0` exists, then add only that unix-char
device and read it back. Stop if any assumption differs.

For every batch below:

1. Start `zrr-logical-backup.service`, verify its successful result and
   inventory, and verify a fresh Restic snapshot.
2. Stop and remove only that batch's old `home` containers. Never pass `--volumes`.
3. Deploy the new Stack group through Komodo.
4. Check container state, database readiness, Caddy routing, public HTTP, and
   any WebSocket endpoint used by the applications.
5. Continue only when the batch is healthy and interruption stayed below five
   minutes.

Order:

1. `home-edge` and `home-control`
2. `home-monitor`, `home-tools`, and `home-media`
3. `home-automation`, `home-ai`, and `home-immich`
4. `home-backup`

The transition overlay keeps Caddy on both `edge` and `home_default` while old
containers remain. Spark is a normal container on `edge`; it no longer shares
Caddy's network namespace. Restore Scrutiny, Miniflux, and SearxNG. Keep
`gitea-db` running without enabling a Gitea application.

### Batch rollback

On any failure, stop and remove only the new batch's containers without
volumes. Use the frozen `runtime.pre-komodo.yml` with project name `home` to
recreate the same service names, then repeat database and public-path checks.
Do not advance to the next batch until the old batch is restored.

## Finalize the migration

After all 35 containers pass and the old `home` project has no containers:

1. In a follow-up Git change, remove
   `deployments/home/home-edge/compose.migration.yml` and remove it from the
   `home-edge` Stack `file_paths`.
2. Merge and run `home-gitops-apply`; read back
   `CADDY_INGRESS_NETWORKS=edge` and confirm Caddy is detached from
   `home_default`.
3. Inspect `home_default` and remove that exact network only when it has zero
   containers.
4. Remove or disable old scheduled/manual `compose up` entry points. Keep the
   frozen runtime file, logical backup, Restic snapshot, and encrypted Git
   bundle as recovery artifacts.

## Acceptance and rescue

Acceptance requires all of the following:

- exactly 35 target containers, with zero restarting and zero unhealthy;
- exactly nine Komodo-owned Compose projects and no `home` project;
- Git HEAD, each Komodo source revision, and every running image digest agree;
- Scrutiny, Miniflux, and SearxNG login/read checks pass;
- every existing public route, required WebSocket, and database connection passes;
- one low-risk update and one stateful backup-before-deploy update complete;
- old-project rollback, Core database restore, and Core-down CLI rescue drills pass.

If Core is unavailable, use Docker Compose directly only as a documented rescue
path against the already-cloned files in `/etc/komodo/stacks/<stack>`. Do not
edit those files. Restore Core independently, reconcile source revisions, then
return deployment ownership to Komodo before the next change.
