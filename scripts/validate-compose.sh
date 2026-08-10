#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

shopt -s nullglob
compose_files=(deployments/home/*/compose.yml)
[[ ${#compose_files[@]} -eq 9 ]]

for compose_file in "${compose_files[@]}"; do
  if [[ $compose_file == deployments/home/home-edge/compose.yml ]]; then
    docker compose \
      --file "$compose_file" \
      --file deployments/home/home-edge/compose.migration.yml \
      config --no-env-resolution --quiet
  else
    docker compose --file "$compose_file" config --no-env-resolution --quiet
  fi
done

docker compose --file komodo/core/compose.yml config --no-env-resolution --quiet

ruby scripts/check-compose.rb
