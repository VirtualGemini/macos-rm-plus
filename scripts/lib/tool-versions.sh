#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

tool_value() {
  key=$1
  value=$(sed -n "s/^$key=//p" "$ROOT/.tool-versions.lock")
  if [ -z "$value" ]; then
    echo "error: missing tool lock entry: $key" >&2
    exit 1
  fi
  printf '%s\n' "$value"
}
