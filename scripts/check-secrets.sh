#!/usr/bin/env bash
set -euo pipefail

gitleaks git --redact --no-banner --log-opts='--all' .

if ! git diff --cached --quiet; then
  gitleaks git --redact --no-banner --staged .
elif [[ ${GITHUB_ACTIONS:-false} == true && -n ${GITHUB_BASE_REF:-} ]]; then
  gitleaks git --redact --no-banner \
    --log-opts="origin/${GITHUB_BASE_REF}...HEAD" .
elif [[ ${GITHUB_ACTIONS:-false} == true ]] &&
  git rev-parse --verify HEAD^ >/dev/null 2>&1; then
  gitleaks git --redact --no-banner --log-opts='HEAD^..HEAD' .
else
  gitleaks git --redact --no-banner --pre-commit .
fi
