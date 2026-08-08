#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

action_count=$(python3 -c \
  'import tomllib; print(len(tomllib.load(open("komodo/resources/actions.toml", "rb"))["action"]))')

for ((index = 0; index < action_count; index++)); do
  python3 -c \
    'import sys,tomllib; print(tomllib.load(open("komodo/resources/actions.toml", "rb"))["action"][int(sys.argv[1])]["config"]["file_contents"])' \
    "$index" |
    npx --yes --package esbuild@0.25.9 \
      esbuild --loader=ts --log-level=error >/dev/null
done

printf '%s Komodo Action scripts parsed as TypeScript\n' "$action_count"
