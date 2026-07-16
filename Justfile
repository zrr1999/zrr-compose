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

compose-up-public:
    just compose-up public

compose-down-home:
    just compose-down home

compose-down-public:
    just compose-down public

compose-down-all:
    just compose-down home
    just compose-down public
