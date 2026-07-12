#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. "$ROOT/scripts/lib/tool-versions.sh"

missing=0

require_command() {
  command_name=$1
  install_hint=$2

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: missing required command '$command_name'" >&2
    echo "hint: $install_hint" >&2
    missing=1
  fi
}

require_command git "install the Xcode Command Line Tools"
require_command make "install the Xcode Command Line Tools"
require_command swift "install an Apple Swift 6 toolchain"
require_command curl "install curl"
require_command tar "install tar"

if [ "$missing" -ne 0 ]; then
  exit 1
fi

expected_swift=$(tool_value swift-language-mode)
swift_version=$(swift --version | sed -n '1s/.*Swift version \([0-9][0-9]*\).*/\1/p')
if [ "$swift_version" != "$expected_swift" ]; then
  echo "error: Swift $expected_swift language support is required" >&2
  swift --version >&2
  exit 1
fi

if ! swift format --version >/dev/null 2>&1; then
  echo "error: the active Swift toolchain does not provide swift-format" >&2
  exit 1
fi

./scripts/install-dev-tools.sh
PATH="$ROOT/.build/tools/bin:$PATH"
export PATH

expected_shellcheck=$(tool_value shellcheck)
shellcheck_version=$(shellcheck --version | sed -n 's/^version: //p')
if [ "$shellcheck_version" != "$expected_shellcheck" ]; then
  echo "error: ShellCheck $expected_shellcheck is required; found $shellcheck_version" >&2
  exit 1
fi

expected_actionlint=$(tool_value actionlint)
actionlint_version=$(actionlint -version 2>&1 | sed -n '1p')
if [ "$actionlint_version" != "$expected_actionlint" ]; then
  echo "error: actionlint $expected_actionlint is required; found $actionlint_version" >&2
  exit 1
fi

swift package resolve

echo "Development toolchain is ready."
echo "Run 'make hooks-install' to enable repository hooks."
