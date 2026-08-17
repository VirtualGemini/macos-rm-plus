# tc 生产式 CLI 退出码无人值守测试

本文档基于
[`tc-production-cli-test-cases.md`](tc-production-cli-test-cases.md)
重新整理，只验证当前生产式 `tc` 的退出码契约。测试不要求人工输入、不打开 Finder、不请求
`sudo`，也不会调用系统 Trash API。

旧文档的带日期反馈是历史证据，其中可能保留退出码 `2`、`3`，以及 JSON 或多输入尚未实现时的
结果。本文件只使用当前契约：

| 退出码 | 含义 |
|---:|---|
| `0` | 命令成功、成功的 dry-run、被忽略的 missing input、有效的短 `-f` 空操作 |
| `1` | 操作失败或安全失败 |
| `64` | 参数解析或命令用法失败 |

## 测试边界

- 默认使用当前仓库构建 Release 二进制，再安装到独立临时目录后执行。也可以通过绝对路径
  `TC_BINARY=/path/to/tc` 指定已经构建且与待测提交一致的 Release 二进制。
- 成功路径使用信息命令、dry-run、空操作或 ignored missing，不移动任何对象。
- 操作失败路径只构造 missing input、不支持类型或 `confirmation_required`；这些失败都发生在
  Trash capability 构造和调用之前。
- 不向确认提示管道输入。非交互确认通过 `--non-interactive` 测试，避免 TTY 差异。
- 只断言进程退出码。stdout 和 stderr 会被捕获，并只在失败时打印，避免把文案变化误判为
  退出码回归。
- 必须由普通 macOS 用户在仓库根目录执行。root 运行会改变真实操作的前置拒绝路径。

## 覆盖矩阵

| 用例范围 | 预期 | 主要覆盖 | 旧用例来源 |
|---|---:|---|---|
| `ES-0-01` 至 `ES-0-09` | `0` | 帮助、版本、附加路径和 `-P` 警告 | TC-78 至 TC-87、TC-146 |
| `ES-0-10` 至 `ES-0-21` | `0` | file/directory/link/FIFO dry-run、JSON、quiet、兼容选项 | TC-01、TC-03、TC-58 至 TC-59、TC-65 至 TC-70、TC-97 至 TC-101、TC-151 |
| `ES-0-22` 至 `ES-0-29` | `0` | ignored missing 及选项覆盖顺序 | TC-13、TC-24、TC-36 至 TC-43、TC-148 至 TC-149 |
| `ES-0-30` 至 `ES-0-39` | `0` | 短 `-f` 无路径空操作和 JSON 空结果 | Exit Status Compatibility 新增矩阵 |
| `ES-1-01` 至 `ES-1-14` | `1` | missing、unsupported kind、非交互确认、JSON/quiet 失败 | TC-12、TC-37、TC-39、TC-43、TC-51、TC-61、TC-102、TC-113 |
| `ES-64-01` 至 `ES-64-33` | `64` | 无输入、无效/冲突选项、strict、信息命令冲突 | TC-18、TC-22、TC-32 至 TC-35、TC-57、TC-71 至 TC-77、TC-82 至 TC-91、TC-117 至 TC-126、TC-134、TC-137、TC-141、TC-147 |

JSON 和多输入当前已经支持。因此 `--json --dry-run`、`--json --verbose --dry-run` 和
`--verbose --json --dry-run` 的成功预期均为 `0`；只有 `--json` 与 `--quiet` 的冲突为
`64`。不要沿用旧反馈中的 `unsupported_output_mode` 或 `unsupported_input_count` 预期。

## 执行脚本

正式测试入口是
[`scripts/run-production-cli-exit-status-tests.sh`](../../scripts/run-production-cli-exit-status-tests.sh)。
脚本打印每个用例的 PASS/FAIL，任一退出码不匹配时最终退出 `1`，全部匹配时退出 `0`。

使用当前仓库重新构建 Release 二进制时：

```console
TC_RESULTS_DIR=docs/manual-testing/results/tc-production-cli-exit-status-current \
  ./scripts/run-production-cli-exit-status-tests.sh
```

使用已经构建且与待测代码一致的 Release 二进制时：

```console
TC_BINARY="$PWD/.build/release/tc" \
TC_RESULTS_DIR=docs/manual-testing/results/tc-production-cli-exit-status-current \
  ./scripts/run-production-cli-exit-status-tests.sh
```

每次运行会持久化以下证据，不再只产生终端摘要：

- `report.md`：运行元数据、汇总和全部 86 个用例的 expected/actual 表；
- `cases.tsv`：机器可读的逐用例退出码与命令；
- `responses.log`：每个用例的完整 stdout、stderr 和实际退出码；
- `run.log`：终端 PASS/FAIL 响应；
- `metadata.txt`：提交、二进制 SHA-256、runner 与 normalization helper 的 SHA-256、版本和起止时间。

提交这些证据前，脚本会把仓库绝对路径以及临时 fixture 根目录的逻辑路径和物理路径分别规范化为
`REPO_ROOT` 与 `TEST_ROOT`，并把仓库内的构建产物记录为
`REPO_ROOT/.build/release/tc`。因此报告不会固化维护者本地 checkout 的名称、绝对路径或主机特有的
临时目录别名。

下面的代码块保留测试命令矩阵供审阅；生成正式证据时必须运行仓库脚本。

```sh
#!/bin/sh

set -u

REPO_ROOT=$(CDPATH='' cd -- "${REPO_ROOT:-.}" && pwd) || exit 1

if [ "$(id -u)" -eq 0 ]; then
  echo 'FAIL setup: run this suite as a non-root macOS user' >&2
  exit 1
fi

if [ -n "${TC_BINARY:-}" ]; then
  SOURCE_TC=$TC_BINARY
  if [ "${SOURCE_TC#/}" = "$SOURCE_TC" ] || [ ! -x "$SOURCE_TC" ]; then
    echo 'FAIL setup: TC_BINARY must be an absolute path to an executable' >&2
    exit 1
  fi
else
  if ! make -C "$REPO_ROOT" build-release; then
    echo 'FAIL setup: release build failed' >&2
    exit 1
  fi
  SOURCE_TC="$REPO_ROOT/.build/release/tc"
fi

TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/tc-exit-status.XXXXXX") || exit 1
WORK_DIR="$TEST_ROOT/work"
RESULTS_DIR="$TEST_ROOT/results"
BIN_DIR="$TEST_ROOT/bin"

trap 'rm -rf -- "$TEST_ROOT"' EXIT
trap 'exit 1' HUP INT TERM

mkdir -p "$WORK_DIR" "$RESULTS_DIR" "$BIN_DIR" || exit 1
install -m 755 "$SOURCE_TC" "$BIN_DIR/tc" || exit 1
TC="$BIN_DIR/tc"

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

  stdout_file="$RESULTS_DIR/$case_id.stdout"
  stderr_file="$RESULTS_DIR/$case_id.stderr"

  "$TC" "$@" >"$stdout_file" 2>"$stderr_file"
  actual_exit=$?
  total=$((total + 1))

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    passed=$((passed + 1))
    printf 'PASS %-10s expected=%s actual=%s\n' "$case_id" "$expected_exit" "$actual_exit"
    return
  fi

  failed=$((failed + 1))
  printf 'FAIL %-10s expected=%s actual=%s\n' "$case_id" "$expected_exit" "$actual_exit"
  printf '%s\n' '--- stdout ---'
  sed -n '1,40p' "$stdout_file"
  printf '%s\n' '--- stderr ---'
  sed -n '1,40p' "$stderr_file"
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

printf '\nSUMMARY total=%s passed=%s failed=%s\n' "$total" "$passed" "$failed"

if [ "$failed" -ne 0 ]; then
  exit 1
fi
exit 0
```

## 通过标准

- 汇总必须为 `SUMMARY total=86 passed=86 failed=0`。
- 脚本自身退出码必须为 `0`。
- `report.md`、`cases.tsv`、`responses.log`、`run.log` 和 `metadata.txt` 必须全部生成。
- 运行期间不应出现 CLI 确认提示、Finder Automation 提示或新的废纸篓项目。

## Canonical evidence 状态

迁移前的运行结果已随产品身份迁移删除，不能改名后继续作为 canonical evidence。当前状态为待生成；
breaking migration 及其修复通过双轴 review 后，将在独立的 evidence commit 中使用 canonical
可执行文件、命令和路径重新运行并提交结果。

以下分支不在本生产 CLI 脚本中强制构造：真实移动成功、系统 Trash 调用失败、Moved Trash
Warning、逐项确认拒绝/中断、root 拒绝、Protected Path 身份比较、无法取得安全身份以及无法访问的
文件系统对象。这些分支需要可注入 capability 或受保护的真实文件系统环境，应继续由
`make test-unit` 中的 `ExitStatusCompatibilityTests`、`ConfirmationCLIApplicationTests`、
`TrashOperationFailureCLIApplicationTests`、`JSONOutputTests` 和相关安全测试验证。纯测试同样不调用
真实 Trash API，也不需要人工接入。
