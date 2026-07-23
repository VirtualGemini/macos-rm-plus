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

cat >"$repo/Sources/RMPPlatform/WorkspaceTrashClient.swift" <<'EOF'
NSWorkspace.shared.recycle([sourceURL], completionHandler: completion)
EOF
cat >"$repo/Sources/rmp/main.swift" <<'EOF'
let client = WorkspaceTrashClient()
EOF
cat >"$repo/TestSupport/RMPTestSafety/WhitelistedTrashClient.swift" <<'EOF'
let client = WorkspaceTrashClient()
EOF
cat >"$repo/Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift" <<'EOF'
let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)
EOF
cat >"$repo/Tests/RMPPlatformTests/WhitelistedTrashClientTests.swift" <<'EOF'
let client = WhitelistedTrashClient.testingOnly(
  context: context,
  authorization: authorization,
  systemTrash: spy.call
)
EOF
cat >"$repo/TestSupport/rmp-test/main.swift" <<'EOF'
print("safe")
EOF

"$repo/scripts/check-system-trash-boundary.sh"

cat >"$repo/Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift" <<'EOF'
let client = WorkspaceTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash production construction escaped through its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift" <<'EOF'
let client: WorkspaceTrashClient = .init()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash production .init escaped through its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift" <<'EOF'
typealias TemporaryProductionTrashClient = WorkspaceTrashClient
let client = TemporaryProductionTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: aliased Workspace Trash production construction escaped its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift" <<'EOF'
let constructor = WorkspaceTrashClient.init
let client = constructor()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash production constructor reference escaped its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift" <<'EOF'
let injected = WorkspaceTrashClient(workspaceRecycle: spy.call)
let production = type(of: injected).init()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash metatype construction escaped its injection test" >&2
  exit 1
fi
cat >"$repo/Tests/RMPPlatformTests/WorkspaceTrashClientTests.swift" <<'EOF'
let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)
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
  echo "test failure: direct Workspace Trash escaped the capability boundary" >&2
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
print("safe again")
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
let client = WorkspaceTrashClient()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash client escaped approved production or whitelist wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client = makeInjectedWorkspaceTrashClient(workspaceRecycle: spy.call)
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash injection factory escaped its adapter test" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
let client: WorkspaceTrashClient = .init()
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash client type reference escaped approved wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
typealias UncheckedTrashClient = WorkspaceTrashClient
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash client type alias escaped approved wiring" >&2
  exit 1
fi

cat >"$repo/FutureTarget/Bypass.swift" <<'EOF'
func makeUncheckedTrashClient() -> WorkspaceTrashClient {
  .init()
}
EOF
if "$repo/scripts/check-system-trash-boundary.sh" >/dev/null 2>&1; then
  echo "test failure: Workspace Trash client factory escaped approved wiring" >&2
  exit 1
fi

echo "System Trash boundary tests passed."
