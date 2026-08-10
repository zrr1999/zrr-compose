#!/usr/bin/env bash
set -euo pipefail

readonly schema_url='https://raw.githubusercontent.com/moghtech/komodo/v2.2.0/ui/public/schema/resources.json'
readonly schema_sha256='131df80fda40fdb405fa6ae8c3116ff88ffc086037d41ea48e0a80a6b001ed6e'

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

schema_file=$(mktemp /tmp/komodo-resources-v2.2.0.XXXXXX.json)
trap 'rm -f -- "$schema_file"' EXIT

curl --fail --silent --show-error --location "$schema_url" --output "$schema_file"
if command -v sha256sum >/dev/null; then
  actual_sha256=$(sha256sum "$schema_file" | awk '{print $1}')
else
  actual_sha256=$(shasum --algorithm 256 "$schema_file" | awk '{print $1}')
fi
[[ $actual_sha256 == "$schema_sha256" ]]

uv run --no-project --with jsonschema==4.25.1 \
  python scripts/validate-komodo-schema.py \
  "$schema_file" \
  komodo/bootstrap-resource-sync.toml \
  komodo/resources/*.toml
