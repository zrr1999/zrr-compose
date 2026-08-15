#!/usr/bin/env bash
set -euo pipefail

[[ ${CI:-} == true ]]
[[ ${GITHUB_ACTIONS:-} == true ]]

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

compose_file=deployments/home/home-control/compose.yml
proxy_source=deployments/home/home-control/configs/spark/loopback-proxy.mjs
proxy_target=/etc/komodo/stacks/home-control/deployments/home/home-control/configs/spark/loopback-proxy.mjs
network_name=spark-proxy
project_name=home-control-ci
network_created=false
stack_started=false

cleanup() {
  if [[ $stack_started == true ]]; then
    docker compose --project-name "$project_name" --file "$compose_file" \
      down --remove-orphans >/dev/null
  fi
  if [[ $network_created == true ]]; then
    docker network rm "$network_name" >/dev/null
  fi
}
trap cleanup EXIT

if docker network inspect "$network_name" >/dev/null 2>&1; then
  echo "refusing to reuse existing $network_name during CI smoke" >&2
  exit 1
fi

sudo install -d -o 1000 -g 1000 /root/zrr-compose/volumes/spark
sudo install -d -m 0755 "$(dirname -- "$proxy_target")"
sudo install -m 0444 "$proxy_source" "$proxy_target"

docker network create --internal "$network_name" >/dev/null
network_created=true
docker compose --project-name "$project_name" --file "$compose_file" \
  up --detach --no-deps spark
stack_started=true

health=starting
for _ in {1..60}; do
  health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' spark)
  [[ $health != healthy ]] || break
  [[ $(docker inspect --format '{{.State.Running}}' spark) == true ]] || break
  sleep 1
done
if [[ $health != healthy ]]; then
  docker inspect --format '{{json .State}}' spark
  docker logs spark
  exit 1
fi

spark_image_ref=$(docker inspect --format '{{.Config.Image}}' spark)
spark_image_id=$(docker inspect --format '{{.Image}}' spark)
echo "Spark runtime image: $spark_image_ref ($spark_image_id)"
if [[ $spark_image_id != sha256:* ]]; then
  echo "Spark runtime image has no content ID" >&2
  exit 1
fi
docker run --rm --network "$network_name" "$spark_image_id" node -e '
  const response = await fetch("http://spark:5173/api/v1/health", {
    headers: {
      host: "spark.zrr.dev",
      "x-forwarded-for": "127.0.0.1",
      "x-forwarded-proto": "https",
    },
  });
  const body = await response.json();
  if (!response.ok || body?.service !== "spark-hub" || body?.status !== "ok") {
    throw new Error(`Spark proxy smoke failed: ${response.status} ${JSON.stringify(body)}`);
  }
'

if [[ $(docker network inspect --format '{{.Internal}}' "$network_name") != true ]]; then
  echo "$network_name is not internal" >&2
  exit 1
fi
members=$(docker network inspect \
  --format '{{range .Containers}}{{println .Name}}{{end}}' "$network_name" | sed '/^[[:space:]]*$/d' | sort | paste -sd ' ' -)
if [[ $members != spark ]]; then
  echo "$network_name has unexpected members: $members" >&2
  exit 1
fi

echo "spark compose smoke: 0.4.0 is healthy through the isolated loopback adapter"
