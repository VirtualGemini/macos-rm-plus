#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/rmp-system-trash-boundary-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM

repo="$TEMP_DIR/repo"
mkdir -p \
  "$repo/scripts" \
  "$repo/Sources" \
  "$repo/Sources/RMPPlatform" \
  "$repo/Sources/rmp" \
  "$repo/TestSupport/RMPTestSafety" \
  "$repo/Tests/RMPPlatformTests" \
  "$repo/TestSupport/rmp-test" \
  "$repo/FutureTarget"
cp "$ROOT/scripts/check-system-trash-boundary.sh" "$repo/scripts/"

cat >"$repo/Sources/RMPPlatform/FinderTrashClient.swift" <<'EOF'
let script = NSAppleScript(source: "tell application id \"com.apple.finder\"")
let event = NSAppleEventDescriptor.list()
EOF
cat >"$repo/TestSupport/RMPTestSafety/FoundationSymlinkTrashClient.swift" <<'EOF'
let client = FileManager.default
try client.trashItem(at: target, resultingItemURL: &result)
EOF
cat >"$repo/Sources/rmp/main.swift" <<'EOF'
let client = MacOSTrashClient()
EOF
cat >"$repo/Sources/RMPPlatform/MacOSTrashClient.swift" <<'EOF'
let finder = FinderTrashClient()
try FileManager.default.trashItem(at: target, resultingItemURL: &result)
EOF
cat >"$repo/TestSupport/RMPTestSafety/WhitelistedTrashClient.swift" <<'EOF'
let client = FinderTrashClient()
let symlinkClient = FoundationSymlinkTrashClient()
EOF
cat >"$repo/TestSupport/RMPTestSafety/WhitelistedPutBackClient.swift" <<'EOF'
let script = NSAppleScript(source: "tell application id \"com.apple.finder\"")
let event = NSAppleEventDescriptor.list()
EOF
cat >"$repo/TestSupport/RMPTestSafety/PutBackRaceAcceptance.swift" <<'EOF'
let client = WhitelistedPutBackClient(context: context)
EOF
cat >"$repo/Tests/RMPPlatformTests/FinderTrashClientTests.swift" <<'EOF'
let client = makeInjectedFinderTrashClient(finderDelete: spy.call)
EOF
cat >"$repo/Tests/RMPPlatformTests/MacOSTrashClientTests.swift" <<'EOF'
let client = makeInjectedMacOSTrashClient(
  finderTrash: finder.call,
  foundationTrash: foundation.call
)
EOF
cat >"$repo/TestSupport/RMPTestSafety/WhitelistedMacOSTrashClient.swift" <<'EOF'
let client = makeInjectedMacOSTrashClient(
  finderTrash: finder.call,
  foundationTrash: foundation.call
)
EOF
cat >"$repo/Tests/RMPPlatformTests/FoundationSymlinkTrashClientTests.swift" <<'EOF'
let client = FoundationSymlinkTrashClient(systemTrash: spy.call)
EOF
cat >"$repo/Tests/RMPPlatformTests/WhitelistedTrashClientTests.swift" <<'EOF'
let client = WhitelistedTrashClient.testingOnly(
  context: context,
  authorization: authorization,
  systemTrash: spy.call
)
EOF
cat >"$repo/Tests/RMPPlatformTests/FoundationTrashFinalizerTests.swift" <<'EOF'
let client = WhitelistedTrashClient.testingOnly(
  context: context,
  authorization: authorization,
  systemTrash: spy.call
)
EOF
cat >"$repo/Tests/RMPPlatformTests/WhitelistedMacOSTrashClientTests.swift" <<'EOF'
let client = WhitelistedTrashClient.testingOnly(
  context: context,
  authorization: authorization,
  systemTrash: spy.call
)
EOF
cat >"$repo/Tests/RMPPlatformTests/PutBackRaceAcceptanceTests.swift" <<'EOF'
let client = WhitelistedPutBackClient(
  context: context,
  resourceIdentifier: resourceIdentifier,
  systemPutBack: spy.call
)
EOF
cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
print("safe")
EOF

"$repo/scripts/check-system-trash-boundary.sh"

cat >"$repo/Tests/RMPPlatformTests/FinderTrashClientTests.swift" <<'EOF'
let client = FinderTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash production construction escaped through its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/FinderTrashClientTests.swift" <<'EOF'
let client: FinderTrashClient = .init()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash production .init escaped through its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/FinderTrashClientTests.swift" <<'EOF'
typealias TemporaryProductionTrashClient = FinderTrashClient
let client = TemporaryProductionTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: aliased Finder Trash production construction escaped its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/FinderTrashClientTests.swift" <<'EOF'
let constructor = FinderTrashClient.init
let client = constructor()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash production constructor reference escaped its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/FinderTrashClientTests.swift" <<'EOF'
let injected = FinderTrashClient(finderDelete: spy.call)
let production = type(of: injected).init()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash metatype construction escaped its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/FinderTrashClientTests.swift" <<'EOF'
let client = makeInjectedFinderTrashClient(finderDelete: spy.call)
EOF

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
try FileManager.default.trashItem(at: target, resultingItemURL: nil)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: legacy Foundation Trash escaped the capability boundary" >&2
  exit 1
fi

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
NSWorkspace.shared.recycle([target], completionHandler: completion)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: failed Workspace Trash candidate escaped the capability boundary" >&2
  exit 1
fi

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
let recycle = NSWorkspace.shared.recycle
recycle([target], completion)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash function reference escaped the capability boundary" >&2
  exit 1
fi

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
let script = NSAppleScript(source: "return 1")
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: direct NSAppleScript escaped the capability boundary" >&2
  exit 1
fi

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
let event = NSAppleEventDescriptor.list()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: direct Apple Event construction escaped the capability boundary" >&2
  exit 1
fi

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: osascript execution escaped the capability boundary" >&2
  exit 1
fi

cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
print("safe again")
EOF

cat >"$repo/TestSupport/RMPTestSafety/PutBackRaceAcceptance.swift" <<'EOF'
let script = NSAppleScript(source: "return 1")
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Put Back automation escaped its isolated adapter" >&2
  exit 1
fi
cat >"$repo/TestSupport/RMPTestSafety/PutBackRaceAcceptance.swift" <<'EOF'
let client = WhitelistedPutBackClient(context: context)
EOF

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client: WhitelistedTrashClient = .testingOnly(
  context: context,
  authorization: .accepting,
  systemTrash: { url in url }
)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: production-like test code constructed an injectable Trash client" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client = FinderTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash client escaped approved production or whitelist wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client = MacOSTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: macOS Trash client escaped approved production wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client = makeInjectedMacOSTrashClient(
  finderTrash: finder.call,
  foundationTrash: foundation.call
)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: macOS Trash injection factory escaped its adapter test" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client = WhitelistedPutBackClient(context: context)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Put Back client escaped its acceptance wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client = FoundationSymlinkTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Foundation symbolic-link Trash client escaped approved test wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client = makeInjectedFinderTrashClient(finderDelete: spy.call)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash injection factory escaped its adapter test" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client: FinderTrashClient = .init()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash client type reference escaped approved wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
typealias UncheckedTrashClient = FinderTrashClient
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash client type alias escaped approved wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
func makeUncheckedTrashClient() -> FinderTrashClient {
  .init()
}
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Finder Trash client factory escaped approved wiring" >&2
  exit 1
fi

echo "System Trash boundary tests passed."
