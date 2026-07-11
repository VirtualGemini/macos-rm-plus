#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TOOLS_BIN="$ROOT/.build/tools/bin"
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-tools.XXXXXX")

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

case "$shellcheck_os-$checksum_arch" in
  darwin-arm64) shellcheck_sha=56affdd8de5527894dca6dc3d7e0a99a873b0f004d7aabc30ae407d3f48b0a79 ;;
  darwin-x86_64) shellcheck_sha=3c89db4edcab7cf1c27bff178882e0f6f27f7afdf54e859fa041fca10febe4c6 ;;
  linux-arm64) shellcheck_sha=12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588 ;;
  linux-x86_64) shellcheck_sha=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198 ;;
esac

case "$actionlint_os-$checksum_arch" in
  darwin-arm64) actionlint_sha=aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f ;;
  darwin-x86_64) actionlint_sha=5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644 ;;
  linux-arm64) actionlint_sha=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6 ;;
  linux-x86_64) actionlint_sha=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8 ;;
esac

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
  shellcheck_asset="shellcheck-v0.11.0.$shellcheck_os.$shellcheck_arch.tar.xz"
  shellcheck_archive="$TEMP_DIR/$shellcheck_asset"
  curl --fail --location --silent --show-error \
    "https://github.com/koalaman/shellcheck/releases/download/v0.11.0/$shellcheck_asset" \
    --output "$shellcheck_archive"
  verify_sha256 "$shellcheck_sha" "$shellcheck_archive"
  tar -xJf "$shellcheck_archive" -C "$TEMP_DIR"
  install -m 0755 "$TEMP_DIR/shellcheck-v0.11.0/shellcheck" "$TOOLS_BIN/shellcheck"
fi

if [ ! -x "$TOOLS_BIN/actionlint" ]; then
  actionlint_asset="actionlint_1.7.12_${actionlint_os}_${actionlint_arch}.tar.gz"
  actionlint_archive="$TEMP_DIR/$actionlint_asset"
  curl --fail --location --silent --show-error \
    "https://github.com/rhysd/actionlint/releases/download/v1.7.12/$actionlint_asset" \
    --output "$actionlint_archive"
  verify_sha256 "$actionlint_sha" "$actionlint_archive"
  tar -xzf "$actionlint_archive" -C "$TEMP_DIR"
  install -m 0755 "$TEMP_DIR/actionlint" "$TOOLS_BIN/actionlint"
fi
