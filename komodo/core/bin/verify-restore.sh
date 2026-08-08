#!/usr/bin/env bash
set -euo pipefail

readonly mongo_image='mongo:8.0.28@sha256:98605bfa1bb2a15dd82109e1d78ad31527a9a744909fab4606076fa71a0ae515'
readonly cli_image='ghcr.io/moghtech/komodo-cli:2.2.0@sha256:f6c5ba5835b584181b5faaeb86ca7bd0a116286696fc5fd7d63b7d724c5a60ce'
readonly container_name=komodo-restore-drill-mongo
readonly network_name=komodo-restore-drill
readonly backup_root=/var/lib/komodo/backups
readonly core_env=/etc/komodo/core.env
readonly target_database=komodo-restore-drill

[[ $EUID -eq 0 ]]
[[ -r "$core_env" ]]
[[ $(stat -c '%a' "$core_env") == 600 ]]

read_env() {
  local key=$1
  local value
  value=$(sed -n "s/^${key}=//p" "$core_env" | tail -n 1)
  [[ -n "$value" ]]
  printf '%s' "$value"
}

username=$(read_env KOMODO_DATABASE_USERNAME)
password=$(read_env KOMODO_DATABASE_PASSWORD)

latest_backup=
for candidate in "$backup_root"/20*; do
  [[ -d "$candidate" ]] || continue
  latest_backup=$candidate
done
[[ -n "$latest_backup" ]]
restore_folder=${latest_backup##*/}

if docker container inspect "$container_name" >/dev/null 2>&1; then
  echo "Refusing to reuse existing container: $container_name" >&2
  exit 1
fi
if docker network inspect "$network_name" >/dev/null 2>&1; then
  echo "Refusing to reuse existing network: $network_name" >&2
  exit 1
fi

cleanup() {
  docker container rm --force "$container_name" >/dev/null 2>&1 || true
  docker network rm "$network_name" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create "$network_name" >/dev/null
docker run --detach \
  --name "$container_name" \
  --network "$network_name" \
  --env MONGO_INITDB_ROOT_USERNAME="$username" \
  --env MONGO_INITDB_ROOT_PASSWORD="$password" \
  "$mongo_image" \
  --quiet --wiredTigerCacheSizeGB 0.25 >/dev/null

for _ in {1..60}; do
  if docker exec "$container_name" mongosh --quiet \
    --username "$username" \
    --password "$password" \
    --authenticationDatabase admin \
    --eval 'quit(db.adminCommand({ ping: 1 }).ok ? 0 : 2)' >/dev/null; then
    break
  fi
  sleep 1
done
docker exec "$container_name" mongosh --quiet \
  --username "$username" \
  --password "$password" \
  --authenticationDatabase admin \
  --eval 'quit(db.adminCommand({ ping: 1 }).ok ? 0 : 2)' >/dev/null

docker run --rm \
  --network "$network_name" \
  --volume "$backup_root:/backups:ro" \
  --env KOMODO_CLI_DATABASE_TARGET_ADDRESS="$container_name:27017" \
  --env KOMODO_CLI_DATABASE_TARGET_USERNAME="$username" \
  --env KOMODO_CLI_DATABASE_TARGET_PASSWORD="$password" \
  --env KOMODO_CLI_DATABASE_TARGET_DB_NAME="$target_database" \
  "$cli_image" \
  km database restore -y --restore-folder "$restore_folder"

collection_count=$(docker exec "$container_name" mongosh --quiet \
  --username "$username" \
  --password "$password" \
  --authenticationDatabase admin \
  --eval "db.getSiblingDB('$target_database').getCollectionNames().length")
[[ $collection_count =~ ^[0-9]+$ ]]
(( collection_count > 0 ))

printf 'Komodo restore drill passed: %s collections restored from %s\n' \
  "$collection_count" "$restore_folder"
