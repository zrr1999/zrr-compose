#!/usr/bin/env bash
set -euo pipefail

[[ ${GITHUB_ACTIONS:-false} == true ]]

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

sudo install -d -m 0755 /etc/zrr-compose/env /etc/komodo

ruby -ryaml -e '
  Dir["deployments/home/*/compose.yml"].each do |file|
    YAML.safe_load_file(file).fetch("services").each_value do |service|
      Array(service["env_file"]).each do |entry|
        puts(entry.is_a?(Hash) ? entry.fetch("path") : entry)
      end
    end
  end
' | sort -u | while IFS= read -r env_file; do
  [[ $env_file =~ ^/etc/zrr-compose/env/[A-Za-z0-9._-]+\.env$ ]]
  [[ ! -e $env_file ]]
  sudo install -o "$(id -u)" -g "$(id -g)" -m 0600 /dev/null "$env_file"
done

[[ ! -e /etc/komodo/core.env ]]
sudo install -o "$(id -u)" -g "$(id -g)" -m 0600 /dev/null /etc/komodo/core.env
