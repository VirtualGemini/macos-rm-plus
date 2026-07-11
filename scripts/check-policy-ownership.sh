#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

while IFS= read -r path; do
  case "$path" in '' | \#*) continue ;; esac
  if ! grep -Fq "$path @VirtualGemini" "$ROOT/.github/CODEOWNERS"; then
    echo "error: policy file pattern lacks explicit CODEOWNER: $path" >&2
    exit 1
  fi
done <"$ROOT/.policy-files"
