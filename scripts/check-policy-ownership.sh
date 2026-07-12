#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
maintainers=$(grep -E '^@[A-Za-z0-9-]+$' "$ROOT/.github/maintainers.txt")

owners_for_path() {
  path=$1
  owners=
  while read -r pattern candidate_owners; do
    case "$pattern" in '' | \#*) continue ;; esac
    # shellcheck disable=SC2254 # CODEOWNERS patterns are intentional globs.
    case "$path" in $pattern) owners=$candidate_owners ;; esac
  done <"$ROOT/.github/CODEOWNERS"
  printf '%s\n' "$owners"
}

files=$(find "$ROOT" -type f ! -path "$ROOT/.git/*" ! -path "$ROOT/.build/*" \
  | sed "s#^$ROOT/##")
while IFS= read -r policy_pattern; do
  case "$policy_pattern" in '' | \#*) continue ;; esac
  matched=0
  while IFS= read -r path; do
    # shellcheck disable=SC2254 # Policy patterns are intentional globs.
    case "$path" in $policy_pattern) ;; *) continue ;; esac
    matched=1
    owners=$(owners_for_path "$path")
  if [ -z "$owners" ]; then
    echo "error: policy file pattern lacks explicit CODEOWNER: $path" >&2
    exit 1
  fi
  for owner in $owners; do
    printf '%s\n' "$maintainers" | grep -Fxq "$owner" \
      || { echo "error: policy owner is not a trusted maintainer: $owner" >&2; exit 1; }
  done
  done <<EOF
$files
EOF
  [ "$matched" -eq 1 ] || { echo "error: policy pattern matches no files: $policy_pattern" >&2; exit 1; }
done <"$ROOT/.policy-files"
