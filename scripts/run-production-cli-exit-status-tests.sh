#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -u

REPO_ROOT=$(CDPATH='' cd -- "${REPO_ROOT:-.}" && pwd) || exit 1

if [ "$(id -u)" -eq 0 ]; then
  echo 'FAIL setup: run this suite as a non-root macOS user' >&2
  exit 1
fi

if [ -n "${RMP_BINARY:-}" ]; then
  SOURCE_RMP=$RMP_BINARY
  if [ "${SOURCE_RMP#/}" = "$SOURCE_RMP" ] || [ ! -x "$SOURCE_RMP" ]; then
    echo 'FAIL setup: RMP_BINARY must be an absolute path to an executable' >&2
    exit 1
  fi
else
  if ! make -C "$REPO_ROOT" build-release; then
    echo 'FAIL setup: release build failed' >&2
    exit 1
  fi
  SOURCE_RMP="$REPO_ROOT/.build/release/rmp"
fi

RUN_ID=${RMP_RUN_ID:-$(date -u '+%Y%m%dT%H%M%SZ')}
if [ -n "${RMP_RESULTS_DIR:-}" ]; then
  RESULTS_DIR=$RMP_RESULTS_DIR
  case "$RESULTS_DIR" in
    /*) ;;
    *) RESULTS_DIR="$REPO_ROOT/$RESULTS_DIR" ;;
  esac
else
  RESULTS_DIR="$REPO_ROOT/.artifacts/rmp-production-cli-exit-status/$RUN_ID"
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/rmp-exit-status.XXXXXX") || exit 1
WORK_DIR="$TEST_ROOT/work"
BIN_DIR="$TEST_ROOT/bin"
STDOUT_DIR="$TEST_ROOT/stdout"
STDERR_DIR="$TEST_ROOT/stderr"
METADATA_FILE="$RESULTS_DIR/metadata.txt"
CASES_FILE="$RESULTS_DIR/cases.tsv"
RESPONSES_FILE="$RESULTS_DIR/responses.log"
RUN_LOG="$RESULTS_DIR/run.log"
REPORT_FILE="$RESULTS_DIR/report.md"
SCRIPT_PATH="$REPO_ROOT/scripts/run-production-cli-exit-status-tests.sh"

trap 'rm -rf -- "$TEST_ROOT"' EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$WORK_DIR" "$BIN_DIR" "$STDOUT_DIR" "$STDERR_DIR" "$RESULTS_DIR" || exit 1
install -m 755 "$SOURCE_RMP" "$BIN_DIR/rmp" || exit 1
RMP="$BIN_DIR/rmp"

CURRENT_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')
BINARY_SHA256=$(shasum -a 256 "$SOURCE_RMP" 2>/dev/null | awk '{print $1}')
SCRIPT_SHA256=$(shasum -a 256 "$SCRIPT_PATH" 2>/dev/null | awk '{print $1}')
VERSION_OUTPUT=$("$SOURCE_RMP" --version 2>&1)
VERSION_EXIT=$?
STARTED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

{
  printf 'run_id=%s\n' "$RUN_ID"
  printf 'started_at=%s\n' "$STARTED_AT"
  printf 'repository=%s\n' "$REPO_ROOT"
  printf 'commit=%s\n' "$CURRENT_COMMIT"
  printf 'source_binary=%s\n' "$SOURCE_RMP"
  printf 'binary_sha256=%s\n' "$BINARY_SHA256"
  printf 'suite_script=%s\n' "$SCRIPT_PATH"
  printf 'suite_script_sha256=%s\n' "$SCRIPT_SHA256"
  printf 'version_exit=%s\n' "$VERSION_EXIT"
  printf 'version_output=%s\n' "$VERSION_OUTPUT"
  printf 'trash_api=not_requested_by_this_suite\n'
} >"$METADATA_FILE"

printf 'case_id\texpected_exit\tactual_exit\tresult\tcommand\n' >"$CASES_FILE"
: >"$RESPONSES_FILE"
: >"$RUN_LOG"

cd "$WORK_DIR" || exit 1
printf 'present\n' > present-file || exit 1
mkdir directory || exit 1
printf 'nested\n' > directory/nested-file || exit 1
ln -s present-file symbolic-link || exit 1
ln -s no-such-target broken-symbolic-link || exit 1
mkfifo fifo-input || exit 1
printf 'first\n' > first-file || exit 1
printf 'second\n' > second-file || exit 1

total=0
passed=0
failed=0

run_case() {
  expected_exit=$1
  case_id=$2
  shift 2

  stdout_file="$STDOUT_DIR/$case_id"
  stderr_file="$STDERR_DIR/$case_id"
  case_command="$RMP"
  for case_argument in "$@"; do
    case_command="$case_command <$case_argument>"
  done

  "$RMP" "$@" >"$stdout_file" 2>"$stderr_file"
  actual_exit=$?
  total=$((total + 1))

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    result=PASS
    passed=$((passed + 1))
  else
    result=FAIL
    failed=$((failed + 1))
  fi

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$case_id" "$expected_exit" "$actual_exit" "$result" "$case_command" >>"$CASES_FILE"
  {
    printf '[%s]\n' "$case_id"
    printf 'command: %s\n' "$case_command"
    printf 'expected_exit: %s\n' "$expected_exit"
    printf 'actual_exit: %s\n' "$actual_exit"
    printf '%s\n' '--- stdout ---'
    sed -n '1,200p' "$stdout_file"
    printf '%s\n\n' '--- stderr ---'
    sed -n '1,200p' "$stderr_file"
  } >>"$RESPONSES_FILE"

  printf '%s %-10s expected=%s actual=%s\n' "$result" "$case_id" "$expected_exit" "$actual_exit" \
    | tee -a "$RUN_LOG"
  if [ "$result" = FAIL ]; then
    printf '%s\n' '--- stdout ---' | tee -a "$RUN_LOG"
    sed -n '1,40p' "$stdout_file" | tee -a "$RUN_LOG"
    printf '%s\n' '--- stderr ---' | tee -a "$RUN_LOG"
    sed -n '1,40p' "$stderr_file" | tee -a "$RUN_LOG"
  fi
}

# Exit 0: information commands and warnings.
run_case 0 ES-0-01 --help
run_case 0 ES-0-02 --help -a
run_case 0 ES-0-03 --help -zh
run_case 0 ES-0-04 --help -a -zh
run_case 0 ES-0-05 --version
run_case 0 ES-0-06 --help missing-information-path
run_case 0 ES-0-07 --version missing-information-path
run_case 0 ES-0-08 --help -P
run_case 0 ES-0-09 --version -P

# Exit 0: read-only planning, JSON, output modes, and Compatibility Options.
run_case 0 ES-0-10 --dry-run present-file
run_case 0 ES-0-11 --dry-run directory
run_case 0 ES-0-12 --dry-run symbolic-link
run_case 0 ES-0-13 --dry-run broken-symbolic-link
run_case 0 ES-0-14 --dry-run fifo-input
run_case 0 ES-0-15 --dry-run first-file directory second-file
run_case 0 ES-0-16 --quiet --dry-run present-file
run_case 0 ES-0-17 --json --dry-run present-file
run_case 0 ES-0-18 --json --verbose --dry-run present-file
run_case 0 ES-0-19 --verbose --json --dry-run present-file
run_case 0 ES-0-20 -P --dry-run present-file
run_case 0 ES-0-21 -rRdx --dry-run directory

# Exit 0: ignored missing inputs and precedence that preserves ignore-missing.
run_case 0 ES-0-22 --dry-run --ignore-missing missing-input
run_case 0 ES-0-23 --dry-run --ignore-missing missing-input present-file
run_case 0 ES-0-24 --json --dry-run --ignore-missing missing-input
run_case 0 ES-0-25 -f missing-input
run_case 0 ES-0-26 --force missing-input
run_case 0 ES-0-27 --ignore-missing missing-input
run_case 0 ES-0-28 -f --ignore-missing -i missing-input
run_case 0 ES-0-29 -f --confirm=each missing-input

# Exit 0: rm-compatible short -f empty-operation matrix.
run_case 0 ES-0-30 -f
run_case 0 ES-0-31 -if
run_case 0 ES-0-32 -i -f
run_case 0 ES-0-33 -f --confirm=never
run_case 0 ES-0-34 -f --confirm=each
run_case 0 ES-0-35 -f --ignore-missing
run_case 0 ES-0-36 -fI
run_case 0 ES-0-37 -If
run_case 0 ES-0-38 --force -f
run_case 0 ES-0-39 -f --json

# Exit 1: operational failures that cannot reach the system Trash API.
run_case 1 ES-1-01 missing-input
run_case 1 ES-1-02 ""
run_case 1 ES-1-03 --dry-run missing-input
run_case 1 ES-1-04 --json --dry-run missing-input
run_case 1 ES-1-05 --dry-run present-file missing-input
run_case 1 ES-1-06 -fi missing-input
run_case 1 ES-1-07 --force --interactive missing-input
run_case 1 ES-1-08 --ignore-missing -f -i missing-input
run_case 1 ES-1-09 --confirm=never fifo-input
run_case 1 ES-1-10 --non-interactive directory
run_case 1 ES-1-11 --non-interactive first-file second-file
run_case 1 ES-1-12 --json --non-interactive directory
run_case 1 ES-1-13 --quiet missing-input
run_case 1 ES-1-14 -P missing-input

# Exit 64: empty invocation and short -f empty-operation precedence.
run_case 64 ES-64-01
run_case 64 ES-64-02 --dry-run
run_case 64 ES-64-03 --
run_case 64 ES-64-04 --force
run_case 64 ES-64-05 -fi
run_case 64 ES-64-06 -f -i
run_case 64 ES-64-07 -f --ignore-missing --confirm=each
run_case 64 ES-64-08 -f --force

# Exit 64: malformed, unknown, unsupported, and conflicting options.
run_case 64 ES-64-09 --unknown present-file
run_case 64 ES-64-10 -z present-file
run_case 64 ES-64-11 -fz present-file
run_case 64 ES-64-12 --confirm=sometimes present-file
run_case 64 ES-64-13 --confirm= present-file
run_case 64 ES-64-14 --confirm present-file
run_case 64 ES-64-15 --confirm=conditionalOnce present-file
run_case 64 ES-64-16 --json --quiet present-file
run_case 64 ES-64-17 --quiet --json present-file
run_case 64 ES-64-18 -W present-file
run_case 64 ES-64-19 -P -W present-file

# Exit 64: strict Compatibility Option validation.
run_case 64 ES-64-20 --strict-options -r present-file
run_case 64 ES-64-21 -r --strict-options present-file
run_case 64 ES-64-22 --strict-options -R present-file
run_case 64 ES-64-23 --strict-options -d present-file
run_case 64 ES-64-24 --strict-options -x present-file
run_case 64 ES-64-25 --strict-options -P present-file
run_case 64 ES-64-26 --strict-options -W present-file

# Exit 64: invalid information-command combinations.
run_case 64 ES-64-27 -a
run_case 64 ES-64-28 -zh
run_case 64 ES-64-29 --help --version
run_case 64 ES-64-30 --version --help
run_case 64 ES-64-31 --version -a
run_case 64 ES-64-32 --version -zh
run_case 64 ES-64-33 --help --json --quiet

FINISHED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
printf '\nSUMMARY total=%s passed=%s failed=%s\n' "$total" "$passed" "$failed" | tee -a "$RUN_LOG"
printf 'finished_at=%s\n' "$FINISHED_AT" >>"$METADATA_FILE"
printf 'total=%s\npassed=%s\nfailed=%s\n' "$total" "$passed" "$failed" >>"$METADATA_FILE"

{
  printf '# rmp production CLI exit-status test report\n\n'
  printf -- "- Run ID: \`%s\`\n" "$RUN_ID"
  printf -- "- Commit: \`%s\`\n" "$CURRENT_COMMIT"
  printf -- "- Binary SHA-256: \`%s\`\n" "$BINARY_SHA256"
  printf -- "- Test script SHA-256: \`%s\`\n" "$SCRIPT_SHA256"
  printf -- "- Version result: \`%s\` (exit \`%s\`)\n" "$VERSION_OUTPUT" "$VERSION_EXIT"
  printf -- "- Started: \`%s\`\n" "$STARTED_AT"
  printf -- "- Finished: \`%s\`\n" "$FINISHED_AT"
  printf -- "- System Trash API: not requested by this suite\n\n"
  printf '## Summary\n\n'
  printf '| Total | Passed | Failed | Script exit |\n|---:|---:|---:|---:|\n'
  printf '| %s | %s | %s | %s |\n\n' "$total" "$passed" "$failed" "$([ "$failed" -eq 0 ] && echo 0 || echo 1)"
  printf '## Cases\n\n'
  printf '| Case | Expected | Actual | Result | Command |\n|---|---:|---:|---|---|\n'
  tail -n +2 "$CASES_FILE" | while IFS="$(printf '\t')" read -r case_id expected actual result command; do
    printf "| \`%s\` | \`%s\` | \`%s\` | \`%s\` | \`%s\` |\n" \
      "$case_id" "$expected" "$actual" "$result" "$command"
  done
  printf "\nDetailed stdout/stderr responses: [\`responses.log\`](responses.log).\n"
  printf "Machine-readable results: [\`cases.tsv\`](cases.tsv).\n"
  printf "Run metadata: [\`metadata.txt\`](metadata.txt).\n"
} >"$REPORT_FILE"

printf 'RESULTS_DIR=%s\nREPORT=%s\nRESPONSES=%s\n' \
  "$RESULTS_DIR" "$REPORT_FILE" "$RESPONSES_FILE"

if [ "$failed" -ne 0 ]; then
  exit 1
fi
exit 0
