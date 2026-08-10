#!/usr/bin/env bash
set -euo pipefail

git diff --check
git diff --cached --check

if [[ ${GITHUB_ACTIONS:-false} == true ]]; then
  if [[ -n ${GITHUB_BASE_REF:-} ]]; then
    git diff --check "origin/${GITHUB_BASE_REF}...HEAD"
  elif git rev-parse --verify HEAD^ >/dev/null 2>&1; then
    git diff --check HEAD^..HEAD
  fi
fi
