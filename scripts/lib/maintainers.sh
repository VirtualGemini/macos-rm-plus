#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

trusted_maintainers_from_ref() {
  ref=$1
  if git cat-file -e "$ref:.github/maintainers.txt" 2>/dev/null; then
    git show "$ref:.github/maintainers.txt"
  fi
  return 0
}

count_maintainers() {
  awk '
    /^@[A-Za-z0-9-]+$/ { count++ }
    END { print count + 0 }'
}

sole_maintainer_login() {
  awk '
    /^@[A-Za-z0-9-]+$/ { count++; handle = substr($0, 2) }
    END { if (count == 1) print handle }'
}

maintainers_contain_login() {
  login=$1
  grep -Fxq "@$login"
}
