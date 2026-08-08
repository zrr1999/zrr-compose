set shell := ["bash", "-euo", "pipefail", "-c"]

default:
    @just --list

structure:
    ruby scripts/check-compose.rb

compose-config:
    scripts/validate-compose.sh

toml:
    python3 -c 'import glob,tomllib; [tomllib.load(open(path,"rb")) for path in glob.glob("komodo/**/*.toml",recursive=True)]'

komodo-schema:
    scripts/validate-komodo-schema.sh

actions:
    scripts/validate-actions.sh

renovate:
    npx --yes --package renovate@44.14.10 renovate-config-validator renovate.json5

secrets:
    scripts/check-secrets.sh

lint:
    scripts/check-diff.sh
    prek run --all-files

check: structure toml komodo-schema actions compose-config renovate secrets lint
