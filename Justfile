compose-up target:
    #!/usr/bin/env bash
    set -euxo pipefail
    cd composes/{{target}}/
    docker compose pull
    docker compose up -d --remove-orphans

compose-down target:
    #!/usr/bin/env bash
    set -euxo pipefail
    cd composes/{{target}}/
    docker compose down

compose-up-home:
    just compose-up home

compose-down-home:
    just compose-down home

compose-down-all:
    just compose-down home
