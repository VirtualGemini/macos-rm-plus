#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_BIN="$ROOT/.build/tools/bin"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-tools.XXXXXX")
. "$ROOT/scripts/lib/tool-versions.sh"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT HUP INT TERM

os=$(uname -s)
arch=$(uname -m)

case "$os" in
  Darwin)
    shellcheck_os=darwin
    actionlint_os=darwin
    ;;
  Linux)
    shellcheck_os=linux
    actionlint_os=linux
    ;;
  *)
    echo "error: unsupported development host: $os" >&2
    exit 1
    ;;
esac

case "$arch" in
  arm64 | aarch64)
    shellcheck_arch=aarch64
    actionlint_arch=arm64
    checksum_arch=arm64
    ;;
  x86_64 | amd64)
    shellcheck_arch=x86_64
    actionlint_arch=amd64
    checksum_arch=x86_64
    ;;
  *)
    echo "error: unsupported development architecture: $arch" >&2
    exit 1
    ;;
esac

shellcheck_version=$(tool_value shellcheck)
actionlint_version=$(tool_value actionlint)
shellcheck_sha=$(tool_value "shellcheck-$shellcheck_os-$checksum_arch-sha256")
actionlint_sha=$(tool_value "actionlint-$actionlint_os-$checksum_arch-sha256")

verify_sha256() {
  expected=$1
  file=$2

  if command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$file" | awk '{print $1}')
  elif command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$file" | awk '{print $1}')
  else
    echo "error: shasum or sha256sum is required" >&2
    exit 1
  fi

  if [ "$actual" != "$expected" ]; then
    echo "error: checksum mismatch for $file" >&2
    exit 1
  fi
}

mkdir -p "$TOOLS_BIN"

if [ ! -x "$TOOLS_BIN/shellcheck" ]; then
  shellcheck_asset="shellcheck-v$shellcheck_version.$shellcheck_os.$shellcheck_arch.tar.xz"
  shellcheck_archive="$TEMP_DIR/$shellcheck_asset"
  curl --fail --location --silent --show-error \
    "https://github.com/koalaman/shellcheck/releases/download/v$shellcheck_version/$shellcheck_asset" \
    --output "$shellcheck_archive"
  verify_sha256 "$shellcheck_sha" "$shellcheck_archive"
  tar -xJf "$shellcheck_archive" -C "$TEMP_DIR"
  install -m 0755 "$TEMP_DIR/shellcheck-v$shellcheck_version/shellcheck" "$TOOLS_BIN/shellcheck"
fi

if [ ! -x "$TOOLS_BIN/actionlint" ]; then
  actionlint_asset="actionlint_${actionlint_version}_${actionlint_os}_${actionlint_arch}.tar.gz"
  actionlint_archive="$TEMP_DIR/$actionlint_asset"
  curl --fail --location --silent --show-error \
    "https://github.com/rhysd/actionlint/releases/download/v$actionlint_version/$actionlint_asset" \
    --output "$actionlint_archive"
  verify_sha256 "$actionlint_sha" "$actionlint_archive"
  tar -xzf "$actionlint_archive" -C "$TEMP_DIR"
  install -m 0755 "$TEMP_DIR/actionlint" "$TOOLS_BIN/actionlint"
fi
