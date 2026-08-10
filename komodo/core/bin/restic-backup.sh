#!/usr/bin/env bash
set -euo pipefail

backup_root=/var/lib/komodo/backups
key_root=/var/lib/komodo/keys
core_env=/etc/komodo/core.env
core_compose=/opt/komodo/compose.yml
env_file=/etc/komodo/restic.env
max_backup_age_seconds=$((26 * 60 * 60))

[[ $EUID -eq 0 ]]
[[ -r "$env_file" ]]
[[ $(stat -c '%a' "$env_file") == 600 ]]
[[ -d "$key_root" && -f "$core_env" && -f "$core_compose" ]]

latest_backup=
for candidate in "$backup_root"/20*; do
  [[ -d "$candidate" ]] || continue
  latest_backup=$candidate
done
[[ -n "$latest_backup" ]]

now=$(date +%s)
backup_mtime=$(stat -c '%Y' "$latest_backup")
(( now - backup_mtime <= max_backup_age_seconds ))

set -a
# shellcheck disable=SC1090
source "$env_file"
set +a

exec 9>/run/lock/komodo-restic.lock
flock -n 9

restic backup "$backup_root" "$key_root" "$core_env" "$core_compose" \
  --host komodo-core \
  --tag komodo-core \
  --exclude-caches
restic forget \
  --host komodo-core \
  --tag komodo-core \
  --keep-daily 14 \
  --keep-weekly 8 \
  --keep-monthly 12 \
  --prune
