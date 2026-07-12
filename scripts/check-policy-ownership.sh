#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
maintainers=$(grep -E '^@[A-Za-z0-9-]+$' "$ROOT/.github/maintainers.txt")

while IFS= read -r path; do
  case "$path" in '' | \#*) continue ;; esac
  owners=
  while read -r pattern candidate_owners; do
    case "$pattern" in '' | \#*) continue ;; esac
    # shellcheck disable=SC2254 # CODEOWNERS patterns are intentional globs.
    case "$path" in $pattern) owners=$candidate_owners ;; esac
  done <"$ROOT/.github/CODEOWNERS"
  if [ -z "$owners" ]; then
    echo "error: policy file pattern lacks explicit CODEOWNER: $path" >&2
    exit 1
  fi
  for owner in $owners; do
    printf '%s\n' "$maintainers" | grep -Fxq "$owner" \
      || { echo "error: policy owner is not a trusted maintainer: $owner" >&2; exit 1; }
  done
done <"$ROOT/.policy-files"
