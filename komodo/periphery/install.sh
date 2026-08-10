#!/usr/bin/env bash
set -euo pipefail

readonly version=v2.2.0
readonly binary_url="https://github.com/moghtech/komodo/releases/download/${version}/periphery-x86_64"
readonly binary_sha256=ace9007805dbfe75ad73c75c36bb26852fa909d825577f31f5d13eecd3c52660

[[ $EUID -eq 0 ]]
[[ $(uname -m) == x86_64 ]]
command -v curl >/dev/null
command -v sha256sum >/dev/null
command -v systemctl >/dev/null
command -v docker >/dev/null

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmp_binary=$(mktemp /tmp/periphery-v2.2.0.XXXXXX)
trap 'rm -f -- "$tmp_binary"' EXIT

curl --fail --silent --show-error --location "$binary_url" --output "$tmp_binary"
printf '%s  %s\n' "$binary_sha256" "$tmp_binary" | sha256sum --check --status

install -d -m 0700 /etc/komodo /etc/komodo/keys
install -d -m 0750 /etc/komodo/stacks /etc/komodo/repos /etc/komodo/builds
install -m 0755 "$tmp_binary" /usr/local/bin/periphery
install -m 0600 "$script_dir/periphery.config.toml" /etc/komodo/periphery.config.toml
install -m 0644 "$script_dir/periphery.service" /etc/systemd/system/periphery.service

if [[ ! -e /etc/komodo/periphery.env ]]; then
  install -m 0600 /dev/null /etc/komodo/periphery.env
fi

systemctl daemon-reload
systemctl enable periphery.service

cat <<'EOF'
Periphery 2.2.0 is installed but has not been started.
Put the one-time onboarding key in /etc/komodo/periphery.env, verify mode 0600,
then run: systemctl start periphery.service
After the Server is connected, remove the key and restart the service.
EOF
