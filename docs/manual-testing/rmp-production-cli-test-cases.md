# rmp 生产式 CLI 真机测试用例

本文件用于真实 macOS 主机测试。命令均使用安装后的 `rmp`，不使用 `.build/...` 路径。

## 注意事项：环境污染与「放回原处」

真机测试依赖系统废纸篓与 Finder。「放回原处」失败**不一定**是 `rmp` 产品缺陷；常见原因是测试环境污染。`rmp` 只调用 `FileManager.trashItem`，不维护 Finder 的放回路径。

### 已观察到的污染模式

1. **隔离目录已失效**：`TEST_DIR="$(mktemp -d)"` 落在 `/var/folders/.../T/tmp.*`。上一会话、上一 agent 或手动清理后，目录可能已不存在，废纸篓项仍指向该「原处」，Finder 报「`tmp.xxx` 不再存在」。
2. **同名反复进废纸篓**：多轮用例复用 `file-real` 等固定名时，Finder / `.DS_Store` 可能把显示名与陈旧原路径关联；表现为**换了新 tmp 目录仍报旧 tmp 名**。
3. **Finder 最近文件夹缓存**：`~/Library/Preferences/com.apple.finder.plist` 的 `FXRecentFolders` 可能长期保留已死的 `tmp.*` 或易挥发的 `T`。仅清空废纸篓、新建 `TEST_DIR` **不够**，需清理该缓存并重启 Finder。
4. **跨 agent / 跨会话残留**：上一轮未清空的废纸篓项、未删除的旧隔离目录、未重启的 Finder，会污染后续「全部」真实移动用例，看起来像从某次开始产品全面回归。

### 判定：环境问题 vs 产品问题

| 情况 | 更宜归类 |
|------|----------|
| 原目录已不存在，放回失败并点名旧 `tmp.xxx` | **环境问题**，不算 `rmp` 回归 |
| 废纸篓有同名残留 / `FXRecentFolders` 仍含死路径，且清理后恢复 | **环境问题** |
| 原目录仍在、废纸篓干净、Finder 已重启且无死路径缓存，仍放回到错误位置 | 再怀疑 **产品 / 系统 API 边界** |

### 每轮开测前检查（建议强制）

1. Finder 废纸篓项目计数为 **0**（需要时先清空）。
2. 本轮 `TEST_DIR` **仍存在**，且后续真实移动只在该目录内创建对象。
3. `com.apple.finder.plist` 的 `FXRecentFolders` **不含** 已失效的 `tmp.*`（若含：删除对应条目后 `killall Finder` 并重开）。
4. 需要人工「放回原处」时：**先确认原目录存活**，再请人操作；失败时先做环境排查，再记产品缺陷。
5. 可选：真实移动使用带 `RUN_ID` 的唯一文件名（如 `file-real-$RUN_ID`），降低同名关联。

### 污染后的清理步骤（复测前）

```sh
# 1) 清空废纸篓（Finder）
osascript -e 'tell application "Finder" to empty the trash'

# 2) 从 FXRecentFolders 去掉易挥发 tmp（示例：用 Python 过滤 name 以 tmp. 开头或 name 为 T 的项）
#    目标文件：~/Library/Preferences/com.apple.finder.plist

# 3) 删除本机残留的 rmp 隔离临时目录（仅限确认的测试 footprint，勿扫删无关 tmp）
# 4) 重启 Finder
killall Finder
# 5) 重新执行 TC-install：mktemp -d、确认废纸篓为 0、再开始后续用例
```

### 测试安全边界（摘要）

不要使用永久删除方式清理**已验证、仍待放回确认**的对象。先在 Finder 中确认废纸篓和「放回原处」。工作区、HOME、根目录和系统目录不得作为真实移动目标。

## TC-install：安装测试版本 & 搭建测试环境

```sh
make build-release
mkdir -p "$HOME/.local/bin"
install -m 755 .build/release/rmp "$HOME/.local/bin/rmp"
export PATH="$HOME/.local/bin:$PATH"
rehash
command -v rmp
rmp --version
TEST_DIR="$(mktemp -d)"
cd "$TEST_DIR"
```

预期：`command -v rmp` 指向 `$HOME/.local/bin/rmp`；版本命令退出码为 0。

反馈：

```text
日期: 2026-07-14
分支: test/rmp-production-cli
预清理: 清空废纸篓；FXRecentFolders 移除 tmp.Dpnt129azc；killall Finder；废纸篓计数=0
make build-release: 成功
command -v rmp: /Users/virtualgemini/.local/bin/rmp
rmp --version: rmp 0.1.0（exit=0）
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
废纸篓计数: 0
结果: PASS
```

## TC-01：普通文件 dry-run

状态：支持。

```sh
printf 'dry-run\n' > file-dry
rmp --dry-run file-dry
printf 'exit=%s\n' "$?"
test -f file-dry && echo 'source=present'
```

预期退出码：0。stdout 包含 `Would move 1 item to Trash:` 和 `[file] "file-dry"`。文件仍存在，不进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout:
Would move 1 item to Trash:
  [file] "file-dry"
exit=0
source=present
结果: PASS
```

## TC-02：普通文件真实移动

状态：支持。

```sh
printf 'real-file\n' > file-real
rmp file-real
printf 'exit=%s\n' "$?"
test ! -e file-real && echo 'source=absent'
```

预期退出码：0。stdout 形如 `Moved "file-real" to Trash at "<系统返回路径>".`。原文件消失，Finder 中出现文件；“放回原处”后回到当前目录。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-real" to Trash at "/Users/virtualgemini/.Trash/file-real".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-real；放回原处后废纸篓消失
验证: source=present 于 TEST_DIR/file-real；内容 real-file；废纸篓计数=0
结果: PASS
```

## TC-03：目录 dry-run 不递归

状态：支持。

```sh
mkdir -p directory-dry/sub
printf nested > directory-dry/sub/file
rmp --dry-run directory-dry
printf 'exit=%s\n' "$?"
```

预期退出码：0。只出现一个顶层 `[directory] "directory-dry"`，不列出 `sub/file`，目录仍存在。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout:
Would move 1 item to Trash:
  [directory] "directory-dry"
exit=0
dir=present nested=present（未进废纸篓）
结果: PASS
```

## TC-04：`rmp -r directory`

状态：选项支持；交互确认暂不支持（08）。

```sh
mkdir -p directory-r/sub
printf nested > directory-r/sub/file
rmp -r directory-r
printf 'exit=%s\n' "$?"
```

预期退出码：1。stderr 包含 `confirmation_required`；目录仍在原处，不进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "directory-r": confirmation is required before this Trash Input can be moved
exit=1
dir=present nested=present（未进废纸篓）
结果: PASS（交互确认 08 暂不支持，安全失败符合预期）
```

## TC-05：`rmp -rf directory`

状态：支持。

```sh
mkdir -p directory-rf/sub
printf nested > directory-rf/sub/file
rmp -rf directory-rf
printf 'exit=%s\n' "$?"
```

预期退出码：0。整个目录作为一个对象进入废纸篓，不递归输出内部文件，内部文件保持完整。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "directory-rf" to Trash at "/Users/virtualgemini/.Trash/directory-rf".
exit=0
source=absent（移动后）
废纸篓: directory-rf 为单一文件夹对象；内部 sub/file 完整（内容 nested）
人工: 废纸篓可见且结构正确；放回原处成功
验证: source=present 于 TEST_DIR/directory-rf；sub/file=nested；废纸篓计数=0
结果: PASS
```

## TC-06：组合短选项 `-Rfv`

状态：支持。

```sh
mkdir directory-Rfv
rmp -Rfv directory-Rfv
printf 'exit=%s\n' "$?"
```

预期：`-R` 被兼容接受，`-f` 关闭确认，`-v` 输出结果；退出码 0，目录进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "directory-Rfv" to Trash at "/Users/virtualgemini/.Trash/directory-Rfv".
exit=0
source=absent（移动后）
人工: 废纸篓可见 directory-Rfv；放回原处成功
验证: source=present 于 TEST_DIR/directory-Rfv；废纸篓计数=0
结果: PASS
```

## TC-07：组合顺序 `-fi`

状态：解析支持；确认执行暂不支持（08）。

```sh
printf fi > file-fi
rmp -fi file-fi
printf 'exit=%s\n' "$?"
```

预期：后面的 `-i` 覆盖 `-f`；退出码 1；包含 `confirmation_required`；文件仍存在。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-fi": confirmation is required before this Trash Input can be moved
exit=1
source=present（未进废纸篓）
结果: PASS（-i 覆盖 -f；交互确认 08 暂不支持，安全失败）
```

## TC-08：组合顺序 `-if`

状态：支持。

```sh
printf if > file-if
rmp -if file-if
printf 'exit=%s\n' "$?"
```

预期：后面的 `-f` 覆盖 `-i`；退出码 0；文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-if" to Trash at "/Users/virtualgemini/.Trash/file-if".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-if；放回原处成功
验证: source=present 于 TEST_DIR/file-if；内容 if；废纸篓计数=0
结果: PASS
```

## TC-09：选项在路径后

状态：支持。

```sh
printf after > file-after
rmp file-after -f
printf 'exit=%s\n' "$?"
```

预期：等价于 `rmp -f file-after`；退出码 0；`-f` 不被当作文件名。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-after" to Trash at "/Users/virtualgemini/.Trash/file-after".
exit=0
source=absent（移动后）；无名为 -f 的文件
人工: 废纸篓可见 file-after；放回原处成功
验证: source=present 于 TEST_DIR/file-after；内容 after；废纸篓计数=0
结果: PASS
```

## TC-10：`--` 与前导短横线文件名

状态：支持。

```sh
printf special > ./-special
rmp -f -- -special
printf 'exit=%s\n' "$?"
```

预期退出码 0；`-special` 被当作路径并进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "-special" to Trash at "/Users/virtualgemini/.Trash/-special".
exit=0
source=absent（移动后）
人工: 废纸篓可见 -special；放回原处成功
验证: source=present 于 TEST_DIR/-special；内容 special；废纸篓计数=0
结果: PASS
```

## TC-11：`-P` 警告

状态：支持。

```sh
printf secure > file-P
rmp -P file-P
printf 'exit=%s\n' "$?"
```

预期：stderr 包含 `-P does not securely overwrite`；退出码 0；只进入废纸篓，不做覆写。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-P" to Trash at "/Users/virtualgemini/.Trash/file-P".
stderr: rmp: warning: -P does not securely overwrite; the item will only be moved to Trash
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-P；放回原处成功
验证: source=present 于 TEST_DIR/file-P；内容 secure；废纸篓计数=0
结果: PASS
```

## TC-12：missing path 默认失败

状态：支持。

```sh
rmp missing-file
printf 'exit=%s\n' "$?"
```

预期：退出码 1；stderr 包含 `missing_input`；不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: rmp: missing_input: Trash Input does not exist: "missing-file"
exit=1
废纸篓计数=0（未调用 Trash）
结果: PASS
```

## TC-13：`-f` 忽略 missing path

状态：支持。

```sh
rmp -f missing-file
printf 'exit=%s\n' "$?"
```

预期：退出码 0；不报告错误；不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
废纸篓计数=0（未调用 Trash）
结果: PASS
```

## TC-14：符号链接只移动链接

状态：支持。

```sh
printf target > target-file
ln -s "$TEST_DIR/target-file" link-file
rmp link-file
printf 'exit=%s\n' "$?"
cat target-file
```

预期：退出码 0；链接进入废纸篓；目标文件仍存在；最后输出 `target`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
重测: 是（首轮在 put-back 前未先核对 target；本轮按正确顺序重跑）
stdout: Moved "link-file" to Trash at "/Users/virtualgemini/.Trash/link-file".
exit=0
放回前验证: link=absent；target=present 内容 target；废纸篓 link-file 仍为 symlink → TEST_DIR/target-file
人工: 废纸篓可见 link-file（种类=替身）；放回原处成功
放回后验证: link=present（symlink→target-file）；target=present 内容 target；废纸篓计数=0
结果: PASS
```

## TC-15：失效符号链接

状态：支持。

```sh
ln -s "$TEST_DIR/no-such-target" broken-link
rmp broken-link
printf 'exit=%s\n' "$?"
```

预期：退出码 0；失效链接本身进入废纸篓；不报告 `missing_input`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "broken-link" to Trash at "/Users/virtualgemini/.Trash/broken-link".
exit=0
stderr: 空（无 missing_input）
放回前: source=absent；废纸篓 broken-link；no-such-target 仍不存在
人工: 废纸篓可见 broken-link；放回原处成功
放回后: source=present（symlink→no-such-target）；废纸篓计数=0
结果: PASS
```

## TC-16：Protected Path

状态：支持。

```sh
rmp --dry-run /
printf 'root-exit=%s\n' "$?"
rmp --dry-run "$HOME"
printf 'home-exit=%s\n' "$?"
rmp --dry-run "$PWD"
printf 'cwd-exit=%s\n' "$?"
```

预期：三个退出码均为 3；stderr 包含 `protected_path`；不显示计划，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
root-exit=3 stderr: rmp: protected_path (filesystem-root): Protected Path rejected: "/"
home-exit=3 stderr: rmp: protected_path (home-directory): Protected Path rejected: "/Users/virtualgemini"
cwd-exit=3 stderr: rmp: protected_path (current-directory): Protected Path rejected: ".../tmp.tbyfgQFr3V"
stdout 均为空；废纸篓计数=0
结果: PASS
```

## TC-17：`-f` 不能绕过保护

状态：支持。

```sh
rmp -f /
printf 'exit=%s\n' "$?"
```

预期：退出码 3；仍为安全拒绝；不得调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (filesystem-root): Protected Path rejected: "/"
exit=3
stdout: 空；废纸篓计数=0
结果: PASS
```

## TC-18：未知选项

状态：支持拒绝。

```sh
printf unknown > unknown-file
rmp --not-an-option unknown-file
printf 'exit=%s\n' "$?"
```

预期：退出码 2；stderr 包含 `unknown option`；文件仍存在。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unknown option "--not-an-option"
exit=2
source=present（unknown-file 未移动）
废纸篓计数=0
结果: PASS
```

## TC-19：多输入真实执行

状态：暂不支持，09 完成前应安全失败。

```sh
printf a > batch-a
printf b > batch-b
rmp -f batch-a batch-b
printf 'exit=%s\n' "$?"
```

预期：退出码 2；stderr 包含 `unsupported_input_count`；两个文件都仍存在。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
结果: SKIP（状态：暂不支持，09 完成前应安全失败；本轮按「不支持的暂不测试」跳过。相近安全失败已在 TC-63/TC-136 覆盖）
```

## TC-20：交互确认

状态：暂不支持，08 完成前应安全失败且不阻塞。

```sh
printf interactive > interactive-file
rmp -i interactive-file
printf 'exit=%s\n' "$?"
```

预期：命令立即结束；退出码 1；stderr 包含 `confirmation_required`；文件仍存在。如果命令等待输入，按 `Ctrl-C` 终止并将该用例记为失败。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
结果: SKIP（状态：暂不支持交互确认 08；本轮跳过。相近 confirmation_required 已在 TC-04/TC-07/TC-25 等覆盖）
```

## TC-21：JSON 输出

状态：暂不支持，10 完成前应安全失败。

```sh
printf json > json-file
rmp --json json-file
printf 'exit=%s\n' "$?"
```

预期：退出码 2；stderr 包含 `unsupported_output_mode`；文件仍存在，不移动。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
结果: SKIP（状态：JSON 输出暂不支持 10；本轮跳过。相近 unsupported_output_mode 已在 TC-56/TC-118 覆盖）
```

## TC-22：无路径参数

状态：支持拒绝。

```sh
rmp
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 为 `rmp: at least one Trash Input is required`；不检查文件系统，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: at least one Trash Input is required
exit=2
stdout: 空；废纸篓计数未因本用例变化
结果: PASS
备注: TC-19/TC-20/TC-21 状态为暂不支持，本轮跳过
```

## TC-23：长选项 `--force`

状态：支持。

```sh
printf force-long > file-force-long
rmp --force file-force-long
printf 'exit=%s\n' "$?"
test ! -e file-force-long && echo 'source=absent'
```

预期退出码：0。效果与 `-f` 相同；不确认，文件进入废纸篓，stdout 报告系统返回的目标路径。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-force-long" to Trash at "/Users/virtualgemini/.Trash/file-force-long".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-force-long；放回原处成功
验证: source=present 于 TEST_DIR/file-force-long；内容 force-long；废纸篓计数=0
结果: PASS
```

## TC-24：`--force` 忽略 missing path

状态：支持。

```sh
rmp --force missing-force-long
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 和 stderr 均为空；不存在的路径被忽略，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
废纸篓计数未因本用例增加（忽略 missing，不调用 Trash）
结果: PASS
```

## TC-25：长选项 `--interactive`

状态：解析支持；交互确认暂不支持（08）。

```sh
printf interactive-long > file-interactive-long
rmp --interactive file-interactive-long
printf 'exit=%s\n' "$?"
test -f file-interactive-long && echo 'source=present'
```

预期退出码：1。stderr 包含 `confirmation_required`；命令不等待输入，文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-interactive-long": confirmation is required before this Trash Input can be moved
exit=1
source=present（未进废纸篓，命令立即结束）
结果: PASS（交互确认 08 暂不支持，安全失败）
```

## TC-26：条件式确认短选项 `-I`

状态：解析支持；交互确认暂不支持（08）。

```sh
printf conditional-once > file-I
rmp -I file-I
printf 'exit=%s\n' "$?"
test -f file-I && echo 'source=present'
```

预期退出码：1。stderr 包含 `confirmation_required`；当前构建不会静默批准，文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-I": confirmation is required before this Trash Input can be moved
exit=1
source=present（未进废纸篓，命令立即结束）
结果: PASS（交互确认 08 暂不支持，安全失败）
```

## TC-27：`--confirm=smart` 普通文件

状态：支持。

```sh
printf smart-file > file-confirm-smart
rmp --confirm=smart file-confirm-smart
printf 'exit=%s\n' "$?"
test ! -e file-confirm-smart && echo 'source=absent'
```

预期退出码：0。普通文件不需要确认，进入废纸篓；stdout 报告系统返回的目标路径。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-confirm-smart" to Trash at "/Users/virtualgemini/.Trash/file-confirm-smart".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-confirm-smart；放回原处成功
验证: source=present 于 TEST_DIR/file-confirm-smart；内容 smart-file；废纸篓计数=0
结果: PASS
```

## TC-28：`--confirm=smart` 目录

状态：解析支持；目录确认暂不支持（08）。

```sh
mkdir directory-confirm-smart
rmp --confirm=smart directory-confirm-smart
printf 'exit=%s\n' "$?"
test -d directory-confirm-smart && echo 'source=present'
```

预期退出码：1。stderr 包含 `confirmation_required`；目录仍在原处，不进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "directory-confirm-smart": confirmation is required before this Trash Input can be moved
exit=1
source=present（目录未进废纸篓）
结果: PASS（目录确认 08 暂不支持，安全失败）
```

## TC-29：`--confirm=never` 目录

状态：支持。

```sh
mkdir -p directory-confirm-never/sub
printf nested > directory-confirm-never/sub/file
rmp --confirm=never directory-confirm-never
printf 'exit=%s\n' "$?"
test ! -e directory-confirm-never && echo 'source=absent'
```

预期退出码：0。目录作为一个顶层对象整体进入废纸篓，不遍历或逐项输出内部内容。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "directory-confirm-never" to Trash at "/Users/virtualgemini/.Trash/directory-confirm-never".
exit=0
source=absent（移动后）
放回前: 废纸篓为单一目录对象；内部 sub/file=nested 完整
人工: 废纸篓可见且结构正确；放回原处成功
验证: source=present；sub/file=nested；废纸篓计数=0
结果: PASS
```

## TC-30：`--confirm=once`

状态：解析支持；交互确认暂不支持（08）。

```sh
printf confirm-once > file-confirm-once
rmp --confirm=once file-confirm-once
printf 'exit=%s\n' "$?"
test -f file-confirm-once && echo 'source=present'
```

预期退出码：1。stderr 包含 `confirmation_required`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-confirm-once": confirmation is required before this Trash Input can be moved
exit=1
source=present（未进废纸篓）
结果: PASS（交互确认 08 暂不支持，安全失败）
```

## TC-31：`--confirm=each`

状态：解析支持；交互确认暂不支持（08）。

```sh
printf confirm-each > file-confirm-each
rmp --confirm=each file-confirm-each
printf 'exit=%s\n' "$?"
test -f file-confirm-each && echo 'source=present'
```

预期退出码：1。stderr 包含 `confirmation_required`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-confirm-each": confirmation is required before this Trash Input can be moved
exit=1
source=present（未进废纸篓）
结果: PASS（交互确认 08 暂不支持，安全失败）
```

## TC-32：无效确认值

状态：支持拒绝。

```sh
printf invalid-confirm > file-invalid-confirm
rmp --confirm=sometimes file-invalid-confirm
printf 'exit=%s\n' "$?"
test -f file-invalid-confirm && echo 'source=present'
```

预期退出码：2。stderr 包含 `invalid confirmation mode "sometimes"`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: invalid confirmation mode "sometimes"
exit=2
source=present
结果: PASS
```

## TC-33：空确认值

状态：支持拒绝。

```sh
rmp --confirm= file-invalid-confirm
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `invalid confirmation mode ""`；不检查路径，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: invalid confirmation mode ""
exit=2
结果: PASS（不检查路径，不调用 Trash）
```

## TC-34：未公开确认值

状态：支持拒绝。

```sh
rmp --confirm=conditionalOnce file-invalid-confirm
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `invalid confirmation mode "conditionalOnce"`；该内部策略不能通过长选项使用。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: invalid confirmation mode "conditionalOnce"
exit=2
结果: PASS
```

## TC-35：`--confirm` 缺少 `=<mode>`

状态：支持拒绝。

```sh
rmp --confirm file-invalid-confirm
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `unknown option "--confirm"`；只接受 `--confirm=<mode>` 形式。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unknown option "--confirm"
exit=2
结果: PASS（仅接受 --confirm=<mode>）
```

## TC-36：显式 `--ignore-missing`

状态：支持。

```sh
rmp --ignore-missing missing-explicit
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 和 stderr 均为空；不存在的路径被忽略，不改变确认策略。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
废纸篓计数=0
结果: PASS
```

## TC-37：`-f -i` 对 missing path 的覆盖

状态：支持。

```sh
rmp -f -i missing-fi
printf 'exit=%s\n' "$?"
```

预期退出码：1。后面的 `-i` 关闭由 `-f` 启用的 missing 忽略；stderr 包含 `missing_input`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: missing_input: Trash Input does not exist: "missing-fi"
exit=1
结果: PASS（-i 关闭 -f 的 missing 忽略）
```

## TC-38：`-i -f` 对 missing path 的覆盖

状态：支持。

```sh
rmp -i -f missing-if
printf 'exit=%s\n' "$?"
```

预期退出码：0。后面的 `-f` 重新启用 missing 忽略；stdout 和 stderr 均为空。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
结果: PASS（-f 重新启用 missing 忽略）
```

## TC-39：`--force --interactive` 对 missing path 的覆盖

状态：支持。

```sh
rmp --force --interactive missing-force-interactive
printf 'exit=%s\n' "$?"
```

预期退出码：1。后面的 `--interactive` 关闭由 `--force` 启用的 missing 忽略；stderr 包含 `missing_input`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: missing_input: Trash Input does not exist: "missing-force-interactive"
exit=1
结果: PASS
```

## TC-40：`--interactive --force` 对 missing path 的覆盖

状态：支持。

```sh
rmp --interactive --force missing-interactive-force
printf 'exit=%s\n' "$?"
```

预期退出码：0。后面的 `--force` 启用 missing 忽略；stdout 和 stderr 均为空。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
结果: PASS
```

## TC-41：显式 missing 策略不被后续 `-i` 清除

状态：支持。

```sh
rmp --ignore-missing -i missing-explicit-i
printf 'exit=%s\n' "$?"
```

预期退出码：0。显式 `--ignore-missing` 保留；`-i` 只改变确认策略，missing path 被忽略。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
结果: PASS（显式 --ignore-missing 保留）
```

## TC-42：`-f --ignore-missing -i`

状态：支持。

```sh
rmp -f --ignore-missing -i missing-force-explicit-i
printf 'exit=%s\n' "$?"
```

预期退出码：0。显式 missing 策略位于 `-f` 之后，后续 `-i` 不清除它。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
结果: PASS（显式 missing 在 -f 之后，-i 不清除）
```

## TC-43：`--ignore-missing -f -i`

状态：支持。

```sh
rmp --ignore-missing -f -i missing-explicit-force-i
printf 'exit=%s\n' "$?"
```

预期退出码：1。后面的 `-f` 将 missing 策略改为 force 来源，随后 `-i` 将其关闭；stderr 包含 `missing_input`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: missing_input: Trash Input does not exist: "missing-explicit-force-i"
exit=1
结果: PASS（-f 改为 force 来源后 -i 关闭）
```

## TC-44：组合顺序 `-fI`

状态：解析支持；交互确认暂不支持（08）。

```sh
printf fI > file-fI
rmp -fI file-fI
printf 'exit=%s\n' "$?"
test -f file-fI && echo 'source=present'
```

预期退出码：1。后面的 `-I` 将确认策略改为条件式 once；stderr 包含 `confirmation_required`，文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-fI": confirmation is required before this Trash Input can be moved
exit=1
source=present（未进废纸篓）
结果: PASS（-I 覆盖 -f；交互确认 08 暂不支持，安全失败）
```

## TC-45：组合顺序 `-If`

状态：支持。

```sh
printf If > file-If
rmp -If file-If
printf 'exit=%s\n' "$?"
test ! -e file-If && echo 'source=absent'
```

预期退出码：0。后面的 `-f` 将确认策略改为 never，文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-If" to Trash at "/Users/virtualgemini/.Trash/file-if".
exit=0
source=absent（移动后）
放回前: 废纸篓有项；内容 If；系统路径名大小写可能规范化为 file-if
人工: 废纸篓可见 file-if；放回后文件内容为 If
放回后验证: readdir 名为 file-if（APFS 默认大小写不敏感，file-If 与 file-if 同一 inode）；内容 If；位于 TEST_DIR；废纸篓计数=0
Finder 备注: 放回时 Finder 未按预期打开 tmp 目录视图，而是以该文件名呈现（路径仍正确落在 TEST_DIR）。归类为 Finder/卷大小写不敏感展示问题，非 rmp 移动失败；rmp 仅调用 FileManager.trashItem。
结果: PASS（功能：进入废纸篓并回到 TEST_DIR；展示/大小写见备注）
```

## TC-46：`-i --confirm=never`

状态：支持。

```sh
printf i-never > file-i-never
rmp -i --confirm=never file-i-never
printf 'exit=%s\n' "$?"
test ! -e file-i-never && echo 'source=absent'
```

预期退出码：0。后面的显式确认策略覆盖 `-i`，文件无需确认并进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-i-never" to Trash at "/Users/virtualgemini/.Trash/file-i-never".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-i-never；放回原处成功；Finder 展示正常
验证: source=present 于 TEST_DIR/file-i-never；内容 i-never；废纸篓计数=0
结果: PASS
```

## TC-47：`--confirm=never -i`

状态：解析支持；交互确认暂不支持（08）。

```sh
printf never-i > file-never-i
rmp --confirm=never -i file-never-i
printf 'exit=%s\n' "$?"
test -f file-never-i && echo 'source=present'
```

预期退出码：1。后面的 `-i` 覆盖 never；stderr 包含 `confirmation_required`，文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-never-i": confirmation is required before this Trash Input can be moved
exit=1
source=present（未进废纸篓）
结果: PASS（后面的 -i 覆盖 never；交互确认 08 暂不支持，安全失败）
```

## TC-48：短选项 `-v`

状态：支持。

```sh
printf verbose-short > file-v
rmp -v file-v
printf 'exit=%s\n' "$?"
test ! -e file-v && echo 'source=absent'
```

预期退出码：0。stdout 报告移动结果。当前单对象执行中，`-v` 与默认成功输出相同。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-v" to Trash at "/Users/virtualgemini/.Trash/file-v".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-v；放回原处成功
验证: source=present 于 TEST_DIR/file-v；内容 verbose-short；废纸篓计数=0
结果: PASS
```

## TC-49：长选项 `--verbose`

状态：支持。

```sh
printf verbose-long > file-verbose
rmp --verbose file-verbose
printf 'exit=%s\n' "$?"
test ! -e file-verbose && echo 'source=absent'
```

预期退出码：0。stdout 报告移动结果。当前单对象执行中，`--verbose` 与默认成功输出相同。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-verbose" to Trash at "/Users/virtualgemini/.Trash/file-verbose".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-verbose；放回原处成功
验证: source=present 于 TEST_DIR/file-verbose；内容 verbose-long；废纸篓计数=0
结果: PASS
```

## TC-50：`--quiet` 成功输出

状态：支持。

```sh
printf quiet-success > file-quiet
rmp --quiet file-quiet > quiet-success.stdout 2> quiet-success.stderr
status=$?
printf 'exit=%s\n' "$status"
wc -c < quiet-success.stdout
wc -c < quiet-success.stderr
test ! -e file-quiet && echo 'source=absent'
```

预期退出码：0。两个 `wc -c` 都输出 `0`；文件进入废纸篓，成功结果不写 stdout。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
quiet-success.stdout 字节=0；quiet-success.stderr 字节=0
source=absent（移动后）
人工: 废纸篓可见 file-quiet（内容 quiet-success）；放回原处成功
验证: source=present 于 TEST_DIR/file-quiet；内容 quiet-success
环境污染备注: 首次执行因 zsh 只读变量 status 在 rmp 成功后脚本报错，随后重跑，导致废纸篓额外残留 file-quiet 21-12-05-525（时间戳式重名）。该残留不是产品第二份输出逻辑；file-quiet 放回后该残留仍在。
结果: PASS（--quiet 成功静默 + 主对象放回）；残留待清理
```

## TC-51：`--quiet` 不抑制错误

状态：支持。

```sh
rmp --quiet missing-quiet > quiet-error.stdout 2> quiet-error.stderr
status=$?
printf 'exit=%s\n' "$status"
wc -c < quiet-error.stdout
cat quiet-error.stderr
```

预期退出码：1。stdout 文件长度为 0；stderr 包含 `missing_input` 和 `missing-quiet`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=1
stdout 字节=0
stderr: rmp: missing_input: Trash Input does not exist: "missing-quiet"
结果: PASS
```

## TC-52：输出顺序 `--quiet --verbose`

状态：支持。

```sh
printf quiet-verbose > file-quiet-verbose
rmp --quiet --verbose file-quiet-verbose
printf 'exit=%s\n' "$?"
```

预期退出码：0。后面的 `--verbose` 覆盖 quiet；stdout 报告移动结果。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-quiet-verbose" to Trash at "/Users/virtualgemini/.Trash/file-quiet-verbose".
exit=0
source=absent（移动后）
人工: 废纸篓可见 file-quiet-verbose；放回原处成功
验证: source=present 于 TEST_DIR/file-quiet-verbose；内容 quiet-verbose
残留: file-quiet 21-12-05-525 仍在废纸篓（TC-50 误重跑环境污染）
结果: PASS
```

## TC-53：输出顺序 `--verbose --quiet`

状态：支持。

```sh
printf verbose-quiet > file-verbose-quiet
rmp --verbose --quiet file-verbose-quiet > verbose-quiet.stdout 2> verbose-quiet.stderr
status=$?
printf 'exit=%s\n' "$status"
wc -c < verbose-quiet.stdout
wc -c < verbose-quiet.stderr
```

预期退出码：0。后面的 `--quiet` 覆盖 verbose；stdout 和 stderr 文件长度均为 0，文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
verbose-quiet.stdout 字节=0；verbose-quiet.stderr 字节=0
source=absent（移动后）
人工: file-verbose-quiet 放回原处成功
验证: source=present 于 TEST_DIR/file-verbose-quiet；内容 verbose-quiet
残留: file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-54：组合短选项 `-fv`

状态：支持。

```sh
printf fv > file-fv
rmp -fv file-fv
printf 'exit=%s\n' "$?"
```

预期退出码：0。`-f` 关闭确认并启用 missing 忽略，`-v` 保留正常结果输出；文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-fv" to Trash at "/Users/virtualgemini/.Trash/file-fv".
exit=0
source=absent（移动后）
人工: file-fv 放回原处成功
验证: source=present 于 TEST_DIR/file-fv；内容 fv
残留: file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-55：组合短选项 `-iv`

状态：解析支持；交互确认暂不支持（08）。

```sh
printf iv > file-iv
rmp -iv file-iv
printf 'exit=%s\n' "$?"
test -f file-iv && echo 'source=present'
```

预期退出码：1。`-i` 需要确认，`-v` 不绕过确认；stderr 包含 `confirmation_required`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "file-iv": confirmation is required before this Trash Input can be moved
exit=1
source=present
结果: PASS（交互确认 08 暂不支持，安全失败）
```

## TC-56：`--json --verbose`

状态：解析支持；JSON 执行暂不支持（10）。

```sh
printf json-verbose > file-json-verbose
rmp --json --verbose file-json-verbose
printf 'exit=%s\n' "$?"
test -f file-json-verbose && echo 'source=present'
```

预期退出码：2。stderr 包含 `unsupported_output_mode`。后面的 verbose 不会把 JSON 策略改回人类输出，文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported_output_mode for "file-json-verbose": JSON Trash Operation results are not available in this build
exit=2
source=present
结果: PASS（JSON 执行 10 暂不支持，安全失败）
```

## TC-57：`--json --quiet` 冲突

状态：支持拒绝。

```sh
printf json-quiet > file-json-quiet
rmp --json --quiet file-json-quiet
printf 'exit=%s\n' "$?"
test -f file-json-quiet && echo 'source=present'
```

预期退出码：2。stderr 包含 `conflicting options --json and --quiet`；冲突在执行前拒绝。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: conflicting options --json and --quiet
exit=2
source=present
结果: PASS
```

## TC-58：`--json --dry-run`

状态：JSON 结果暂不支持；当前 dry-run 仍输出人类可读计划。

```sh
printf json-dry > file-json-dry
rmp --json --dry-run file-json-dry
printf 'exit=%s\n' "$?"
test -f file-json-dry && echo 'source=present'
```

预期退出码：0。stdout 为 `Would move 1 item to Trash:` 计划，不是 JSON；文件仍在原处。该用例不能作为 JSON 支持通过。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Would move 1 item to Trash: / [file] "file-json-dry"（人类可读，非 JSON）
exit=0
source=present
结果: PASS（符合当前行为；不能作为 JSON 支持通过）
```

## TC-59：`--quiet --dry-run`

状态：支持；dry-run 固定显示计划。

```sh
printf quiet-dry > file-quiet-dry
rmp --quiet --dry-run file-quiet-dry
printf 'exit=%s\n' "$?"
test -f file-quiet-dry && echo 'source=present'
```

预期退出码：0。stdout 仍显示完整 dry-run 计划；quiet 只抑制真实移动的正常成功结果。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Would move 1 item to Trash: / [file] "file-quiet-dry"
exit=0
source=present
结果: PASS（quiet 不抑制 dry-run 计划）
```

## TC-60：`--non-interactive` 普通文件

状态：支持。

```sh
printf non-interactive-file > file-non-interactive
rmp --non-interactive file-non-interactive
printf 'exit=%s\n' "$?"
test ! -e file-non-interactive && echo 'source=absent'
```

预期退出码：0。smart 策略下普通文件无需确认；命令不读取终端，文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-non-interactive" to Trash at "/Users/virtualgemini/.Trash/file-non-interactive".
exit=0
source=absent（移动后）
人工: file-non-interactive 放回原处成功
验证: source=present 于 TEST_DIR/file-non-interactive；内容 non-interactive-file
残留: file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-61：`--non-interactive` 目录

状态：支持安全失败；交互确认暂不支持（08）。

```sh
mkdir directory-non-interactive
rmp --non-interactive directory-non-interactive
printf 'exit=%s\n' "$?"
test -d directory-non-interactive && echo 'source=present'
```

预期退出码：1。命令立即结束且不读取终端；stderr 包含 `confirmation_required`，目录仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: confirmation_required for "directory-non-interactive": confirmation is required before this Trash Input can be moved
exit=1
source=present
结果: PASS（目录确认 08 暂不支持，安全失败）
```

## TC-62：`--stop-on-error` 单对象执行

状态：解析支持；当前单对象执行中无额外效果。

```sh
printf stop-single > file-stop-single
rmp --stop-on-error file-stop-single
printf 'exit=%s\n' "$?"
test ! -e file-stop-single && echo 'source=absent'
```

预期退出码：0。选项被接受；单个文件正常进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-stop-single" to Trash at "/Users/virtualgemini/.Trash/file-stop-single".
exit=0
source=absent（移动后）
人工: file-stop-single 放回原处成功
验证: source=present 于 TEST_DIR/file-stop-single；内容 stop-single
残留: file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-63：`--stop-on-error` 多对象真实执行

状态：解析支持；多对象真实执行暂不支持（09）。

```sh
printf stop-a > file-stop-a
printf stop-b > file-stop-b
rmp --stop-on-error file-stop-a file-stop-b
printf 'exit=%s\n' "$?"
test -f file-stop-a && test -f file-stop-b && echo 'sources=present'
```

预期退出码：2。stderr 包含 `unsupported_input_count`；两个文件都不移动。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported_input_count for "file-stop-a", "file-stop-b": single-item execution requires exactly one Trash Input
exit=2
sources=present（均未移动）
结果: PASS（多对象真实执行 09 暂不支持，安全失败）
```

## TC-64：`--strict-options` 与原生选项

状态：支持。

```sh
printf strict-native > file-strict-native
rmp --strict-options --force file-strict-native
printf 'exit=%s\n' "$?"
test ! -e file-strict-native && echo 'source=absent'
```

预期退出码：0。严格模式不拒绝原生选项；文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-strict-native" to Trash at "/Users/virtualgemini/.Trash/file-strict-native".
exit=0
source=absent（移动后）
人工: file-strict-native 放回原处成功
验证: source=present 于 TEST_DIR/file-strict-native；内容 strict-native
残留: file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-65：兼容选项 `-R`

状态：兼容接受并忽略。

```sh
printf compat-R > file-compat-R
rmp -R file-compat-R
printf 'exit=%s\n' "$?"
```

预期退出码：0。stderr 无兼容警告；文件按普通顶层对象进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-compat-R" to Trash at "/Users/virtualgemini/.Trash/file-compat-R".
exit=0
stderr: 空（无兼容警告）
source=absent（移动后）
人工: file-compat-R 放回原处成功
验证: source=present 于 TEST_DIR/file-compat-R；内容 compat-R
残留: file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-66：兼容选项 `-d`

状态：兼容接受并忽略。

```sh
printf compat-d > file-compat-d
rmp -d file-compat-d
printf 'exit=%s\n' "$?"
```

预期退出码：0。stderr 为空；该选项不改变顶层对象移动行为。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-compat-d" to Trash at "/Users/virtualgemini/.Trash/file-compat-d".
exit=0
stderr: 空
source=absent（移动后）
人工: file-compat-d 放回原处成功
验证: source=present 于 TEST_DIR/file-compat-d；内容 compat-d
残留: file-quiet 21-12-05-525 仍在废纸篓；另见 file-compat-x 环境污染残留
结果: PASS
```

## TC-67：兼容选项 `-x`

状态：兼容接受并忽略。

```sh
printf compat-x > file-compat-x
rmp -x file-compat-x
printf 'exit=%s\n' "$?"
```

预期退出码：0。stderr 为空；不存在用户态递归跨卷过程，文件正常进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-compat-x" to Trash at "/Users/virtualgemini/.Trash/file-compat-x 21-55-21-877".
exit=0
stderr: 空
source=absent（移动后）
说明: 废纸篓已有环境污染残留 file-compat-x，系统同名重命名为 file-compat-x 21-55-21-877
人工: file-compat-x 21-55-21-877 放回原处成功
验证: TEST_DIR 出现 'file-compat-x 21-55-21-877'（保留系统重命名）；内容 compat-x
残留: 旧 file-compat-x 与 file-quiet 21-12-05-525 仍在废纸篓
结果: PASS（-x 兼容接受；同名重命名为系统 Trash 行为）
```

## TC-68：组合兼容选项 `-rdx`

状态：兼容接受并忽略。

```sh
printf compat-rdx > file-compat-rdx
rmp -rdx file-compat-rdx
printf 'exit=%s\n' "$?"
```

预期退出码：0。三个字符均被接受且不产生警告；文件作为一个顶层对象进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-compat-rdx" to Trash at "/Users/virtualgemini/.Trash/file-compat-rdx".
exit=0
stderr: 空（-r/-d/-x 均接受、无警告）
source=absent（移动后）
人工: file-compat-rdx 放回原处成功
验证: source=present 于 TEST_DIR/file-compat-rdx；内容 compat-rdx
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-69：组合短选项 `-rfv`

状态：支持。

```sh
mkdir -p directory-rfv/sub
printf nested > directory-rfv/sub/file
rmp -rfv directory-rfv
printf 'exit=%s\n' "$?"
test ! -e directory-rfv && echo 'source=absent'
```

预期退出码：0。`-r` 被兼容接受，`-f` 关闭确认，`-v` 输出结果；整个目录作为一个对象进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "directory-rfv" to Trash at "/Users/virtualgemini/.Trash/directory-Rfv".
exit=0
source=absent（移动后）
放回前: 单一目录对象；内部 sub/file=nested
人工: directory-Rfv 放回原处成功；结构 directory-Rfv/sub/file
验证: TEST_DIR/directory-Rfv/sub/file 存在；内容 nested
说明: APFS 大小写不敏感，显示名折叠为 directory-Rfv（与 TC-06 同名冲突）
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-70：重复警告选项 `-PP`

状态：兼容接受并逐次警告。

```sh
printf repeated-P > file-PP
rmp -PP file-PP 2> repeated-P.stderr
status=$?
printf 'exit=%s\n' "$status"
cat repeated-P.stderr
```

预期退出码：0。stderr 中 `-P does not securely overwrite` 出现两次；文件只进入废纸篓，不执行覆写。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-PP" to Trash at "/Users/virtualgemini/.Trash/file-PP".
exit=0
stderr: -P warning 出现两次（逐次警告）
source=absent（移动后）
人工: file-PP 放回原处成功
验证: source=present 于 TEST_DIR/file-PP；内容 PP
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-71：不支持的兼容选项 `-W`

状态：支持拒绝。

```sh
printf compat-W > file-compat-W
rmp -W file-compat-W
printf 'exit=%s\n' "$?"
test -f file-compat-W && echo 'source=present'
```

预期退出码：2。stderr 为 `rmp: unsupported Compatibility Option -W`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported Compatibility Option -W
exit=2
source=present
结果: PASS
```

## TC-72：严格模式拒绝 `-r`

状态：支持拒绝。

```sh
printf strict-r > file-strict-r
rmp --strict-options -r file-strict-r
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `Compatibility Option -r is not allowed with --strict-options`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -r is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-73：严格模式拒绝 `-R`

状态：支持拒绝。

```sh
printf strict-R > file-strict-R
rmp --strict-options -R file-strict-R
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `Compatibility Option -R is not allowed with --strict-options`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -R is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-74：严格模式拒绝 `-d`

状态：支持拒绝。

```sh
printf strict-d > file-strict-d
rmp --strict-options -d file-strict-d
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `Compatibility Option -d is not allowed with --strict-options`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -d is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-75：严格模式拒绝 `-x`

状态：支持拒绝。

```sh
printf strict-x > file-strict-x
rmp --strict-options -x file-strict-x
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `Compatibility Option -x is not allowed with --strict-options`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -x is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-76：严格模式拒绝 `-P`

状态：支持拒绝。

```sh
printf strict-P > file-strict-P
rmp --strict-options -P file-strict-P
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `Compatibility Option -P is not allowed with --strict-options`，不输出普通 `-P` 警告；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -P is not allowed with --strict-options
exit=2
source=present（无普通 -P 警告）
结果: PASS
```

## TC-77：严格模式下的 `-W`

状态：支持拒绝。

```sh
printf strict-W > file-strict-W
rmp --strict-options -W file-strict-W
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 为 `unsupported Compatibility Option -W`。`-W` 始终拒绝，不进入无效果兼容项判断。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported Compatibility Option -W
exit=2
source=present
结果: PASS
```

## TC-78：英文主帮助

状态：支持。

```sh
rmp --help
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 包含 `Usage: rmp [OPTIONS] <PATH>...`、`Native options:` 和 `rmp --help -a`；stderr 为空。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
stdout 含 Usage: rmp [OPTIONS] <PATH>...、Native options:、rmp --help -a
stderr: 空
结果: PASS
```

## TC-79：英文兼容帮助

状态：支持。

```sh
rmp --help -a
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 分别包含 `Accepted with no effect`、`Accepted with a warning`、`Unsupported`，并列出 `-r, -R, -d, -x`、`-P` 和 `-W`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
stdout 含 Accepted with no effect / Accepted with a warning / Unsupported 及 -r,-R,-d,-x / -P / -W
结果: PASS
```

## TC-80：中文主帮助

状态：支持。

```sh
rmp --help -zh
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 包含 `用法：rmp [选项] <路径>...`、`原生选项：` 和 `rmp --help -a -zh`；stderr 为空。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
stdout 含 用法：rmp [选项] <路径>...、原生选项：、rmp --help -a -zh
stderr: 空
结果: PASS
```

## TC-81：中文兼容帮助

状态：支持。

```sh
rmp --help -a -zh
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 分别包含 `接受但无效果`、`接受但会警告`、`不支持`，并说明全部兼容选项。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
stdout 含 接受但无效果 / 接受但会警告 / 不支持
结果: PASS
```

## TC-82：孤立帮助修饰符 `-a`

状态：支持拒绝。

```sh
rmp -a
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 为 `rmp: -a is only valid with --help`；不检查文件系统。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: -a is only valid with --help
exit=2
结果: PASS
```

## TC-83：孤立帮助修饰符 `-zh`

状态：支持拒绝。

```sh
rmp -zh
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 为 `rmp: -zh is only valid with --help`；不检查文件系统。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: -zh is only valid with --help
exit=2
结果: PASS
```

## TC-84：帮助与版本冲突

状态：支持拒绝。

```sh
rmp --help --version
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 为 `rmp: --help and --version cannot be used together`；stdout 为空。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: --help and --version cannot be used together
exit=2
stdout: 空
结果: PASS
```

## TC-85：版本命令

状态：支持。

```sh
rmp --version
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 固定为 `rmp 0.1.0`；stderr 为空，不检查路径或 Trash 能力。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: rmp 0.1.0
exit=0
stderr: 空
结果: PASS
```

## TC-86：帮助命令忽略附加路径

状态：支持。

```sh
rmp --help no-such-help-path
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 输出帮助；不存在的附加路径不会触发 `missing_input`，也不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
stdout: 帮助正文
stderr: 无 missing_input
结果: PASS
```

## TC-87：帮助命令保留 `-P` 警告

状态：支持。

```sh
rmp --help -P
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 输出主帮助；stderr 包含一次 `-P does not securely overwrite` 警告。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
exit=0
stdout: 主帮助
stderr: -P does not securely overwrite 出现 1 次
结果: PASS
```

## TC-88：版本命令执行严格模式校验

状态：支持拒绝。

```sh
rmp --version --strict-options -r
printf 'exit=%s\n' "$?"
```

预期退出码：2。stdout 为空；stderr 包含 `Compatibility Option -r is not allowed with --strict-options`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -r is not allowed with --strict-options
exit=2
stdout: 空
结果: PASS
```

## TC-89：信息命令仍执行全局输出冲突校验

状态：支持拒绝。

```sh
rmp --help --json --quiet
printf 'exit=%s\n' "$?"
```

预期退出码：2。stdout 为空；stderr 包含 `conflicting options --json and --quiet`，不输出帮助正文。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: conflicting options --json and --quiet
exit=2
stdout: 空
结果: PASS
```

## TC-90：未知短选项

状态：支持拒绝。

```sh
printf unknown-short > file-unknown-short
rmp -z file-unknown-short
printf 'exit=%s\n' "$?"
test -f file-unknown-short && echo 'source=present'
```

预期退出码：2。stderr 包含 `unknown option "-z"`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unknown option "-z"
exit=2
source=present
结果: PASS
```

## TC-91：组合短选项中的未知字符

状态：支持拒绝。

```sh
printf unknown-cluster > file-unknown-cluster
rmp -fz file-unknown-cluster
printf 'exit=%s\n' "$?"
test -f file-unknown-cluster && echo 'source=present'
```

预期退出码：2。虽然先解析到 `-f`，未知的 `-z` 仍使整条命令失败；文件不移动。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unknown option "-z"
exit=2
source=present
结果: PASS
```

## TC-92：单独的 `-` 作为路径

状态：支持。

```sh
printf dash-file > ./-
rmp -
printf 'exit=%s\n' "$?"
test ! -e ./- && echo 'source=absent'
```

预期退出码：0。单独的 `-` 被当作文件路径，不表示标准输入；文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "-" to Trash at "/Users/virtualgemini/.Trash/-".
exit=0
source=absent（移动后）
人工: 废纸篓名为 - 的项放回原处成功
验证: source=present 于 TEST_DIR/-；内容 dash-file
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-93：相对路径前缀避开选项解析

状态：支持。

```sh
printf relative-hyphen > ./-f
rmp ./-f
printf 'exit=%s\n' "$?"
test ! -e ./-f && echo 'source=absent'
```

预期退出码：0。`./-f` 被当作路径，不被解析为 force；文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "./-f" to Trash at "/Users/virtualgemini/.Trash/-f".
exit=0
source=absent（移动后）
人工: -f 放回原处成功
验证: source=present 于 TEST_DIR/-f；内容 relative-hyphen
说明: ./-f 被当作路径，未解析为 force
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-94：选项位于两个路径之间

状态：解析支持；多对象真实执行暂不支持（09）。

```sh
printf middle-a > file-middle-a
printf middle-b > file-middle-b
rmp file-middle-a -f file-middle-b
printf 'exit=%s\n' "$?"
test -f file-middle-a && test -f file-middle-b && echo 'sources=present'
```

预期退出码：2。`-f` 被识别为选项而不是路径；stderr 包含 `unsupported_input_count`，两个文件都不移动。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported_input_count for "file-middle-a", "file-middle-b": single-item execution requires exactly one Trash Input
exit=2
sources=present（-f 识别为选项；两文件均未移动）
结果: PASS（多对象真实执行 09 暂不支持，安全失败）
```

## TC-95：`--` 位于两个路径之间

状态：解析支持；多对象真实执行暂不支持（09）。

```sh
printf boundary-a > file-boundary-a
printf boundary-b > file-boundary-b
rmp file-boundary-a -- file-boundary-b
printf 'exit=%s\n' "$?"
test -f file-boundary-a && test -f file-boundary-b && echo 'sources=present'
```

预期退出码：2。`--` 结束选项解析但不成为路径；stderr 包含 `unsupported_input_count`，两个文件都不移动。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported_input_count for "file-boundary-a", "file-boundary-b": single-item execution requires exactly one Trash Input
exit=2
sources=present（-- 不成为路径；两文件均未移动）
结果: PASS（多对象真实执行 09 暂不支持，安全失败）
```

## TC-96：长选项位于路径后

状态：支持。

```sh
printf long-after > file-long-after
rmp file-long-after --force
printf 'exit=%s\n' "$?"
test ! -e file-long-after && echo 'source=absent'
```

预期退出码：0。`--force` 在 `--` 之前始终按选项解析，不被当作路径；文件进入废纸篓。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-long-after" to Trash at "/Users/virtualgemini/.Trash/file-long-after".
exit=0
source=absent（移动后）
人工: file-long-after 放回原处成功
验证: source=present 于 TEST_DIR/file-long-after；内容 long-after
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-97：多路径 dry-run 保持输入顺序

状态：支持。

```sh
printf first > dry-order-first
mkdir dry-order-directory
printf third > dry-order-third
rmp --dry-run dry-order-first dry-order-directory dry-order-third
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 依次列出 `[file] "dry-order-first"`、`[directory] "dry-order-directory"`、`[file] "dry-order-third"`；三个对象均保持原状。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout 依次:
Would move 3 items to Trash:
  [file] "dry-order-first"
  [directory] "dry-order-directory"
  [file] "dry-order-third"
exit=0
三对象均仍在原处
结果: PASS
```

## TC-98：空格与 Unicode 路径

状态：支持。

```sh
printf space > 'file with space'
printf unicode > '文件-测试'
rmp --dry-run 'file with space' '文件-测试'
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 完整、按输入顺序显示两个带引号路径；字符不丢失，文件均保持原状。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout:
Would move 2 items to Trash:
  [file] "file with space"
  [file] "文件-测试"
exit=0
两文件均仍在原处
结果: PASS
```

## TC-99：换行、引号与反斜线路径转义

状态：支持。

```sh
newline_name="$(printf 'line\nbreak')"
quote_name='quote"name'
backslash_name='back\slash'
printf newline > "$newline_name"
printf quote > "$quote_name"
printf backslash > "$backslash_name"
rmp --dry-run "$newline_name" "$quote_name" "$backslash_name"
printf 'exit=%s\n' "$?"
```

预期退出码：0。每个对象各占一行；路径分别显示为 `"line\nbreak"`、`"quote\"name"` 和 `"back\\slash"`，不会把控制字符原样写入诊断。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout:
Would move 3 items to Trash:
  [file] "line\nbreak"
  [file] "quote\"name"
  [file] "back\\slash"
exit=0
三对象均仍在原处
结果: PASS
```

## TC-100：只读普通文件

状态：支持。

```sh
printf readonly > file-readonly
chmod 444 file-readonly
rmp file-readonly
printf 'exit=%s\n' "$?"
test ! -e file-readonly && echo 'source=absent'
```

预期退出码：0。文件内容权限不改变顶层废纸篓移动；文件进入废纸篓。放回原处后仍为只读权限。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-readonly" to Trash at "/Users/virtualgemini/.Trash/file-readonly".
exit=0
source=absent（移动后）；废纸篓内 mode=444
人工: file-readonly 放回原处成功；权限仍为只读
验证: source=present 于 TEST_DIR/file-readonly；mode=444；内容 readonly
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-101：不支持类型的 dry-run

状态：dry-run 支持识别并展示。

```sh
mkfifo fifo-dry
rmp --dry-run fifo-dry
printf 'exit=%s\n' "$?"
test -p fifo-dry && echo 'source=present'
```

预期退出码：0。stdout 包含 `[other] "fifo-dry"`；dry-run 只展示计划，不执行移动。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout:
Would move 1 item to Trash:
  [other] "fifo-dry"
exit=0
source=present（fifo 未移动）
结果: PASS
```

## TC-102：不支持类型的真实执行

状态：支持安全拒绝。

```sh
mkfifo fifo-real
rmp fifo-real
printf 'exit=%s\n' "$?"
test -p fifo-real && echo 'source=present'
```

预期退出码：1。stderr 包含 `unsupported_input_kind (rejected)` 和 `fifo-real`；对象仍在原处，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported_input_kind (rejected) for "fifo-real": The Trash Input has an unsupported entry kind.
exit=1
source=present
结果: PASS
```

## TC-103：无法检查的路径

状态：支持安全失败。

```sh
mkdir inaccessible-parent
printf inaccessible > inaccessible-parent/file
chmod 000 inaccessible-parent
rmp --dry-run inaccessible-parent/file
status=$?
printf 'exit=%s\n' "$status"
chmod 700 inaccessible-parent
```

预期退出码：1。stderr 包含 `inaccessible_input` 和 `inaccessible-parent/file`；恢复父目录权限后文件仍存在。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: inaccessible_input: Trash Input cannot be inspected: "inaccessible-parent/file"
exit=1
恢复权限后 file=present
结果: PASS
```

## TC-104：指向受保护目录的符号链接

状态：支持。

```sh
ln -s "$HOME" link-to-home
rmp link-to-home
printf 'exit=%s\n' "$?"
test ! -L link-to-home && echo 'link=absent'
test -d "$HOME" && echo 'home=present'
```

预期退出码：0。只移动符号链接条目，不解析或移动目标目录；用户主目录保持原状。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "link-to-home" to Trash at "/Users/virtualgemini/.Trash/link-to-home".
exit=0
放回前: link=absent；home=present；废纸篓 link-to-home 仍为 symlink → $HOME
人工: link-to-home 放回原处成功；Finder 种类=替身，图标为目录
验证: link=present（symlink→/Users/virtualgemini）；home=present
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-105：根目录等价表达 `//`

状态：支持安全拒绝。

```sh
rmp --dry-run //
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (filesystem-root)`；不显示计划，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (filesystem-root): Protected Path rejected: "//"
exit=3
stdout: 空
结果: PASS
```

## TC-106：当前目录表达 `.`

状态：支持安全拒绝。

```sh
rmp --dry-run .
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (current-directory)`；不显示计划，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (current-directory): Protected Path rejected: "."
exit=3
结果: PASS
```

## TC-107：主目录等价表达

状态：支持安全拒绝。

```sh
rmp --dry-run "$HOME/"
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (home-directory)`；不显示计划，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (home-directory): Protected Path rejected: "/Users/virtualgemini/"
exit=3
结果: PASS
```

## TC-108：父目录表达式 `..`

状态：支持安全拒绝。

```sh
rmp --dry-run ..
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (parent-directory)`；不显示计划，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (parent-directory): Protected Path rejected: ".."
exit=3
结果: PASS
```

## TC-109：`--confirm=never` 不能绕过保护

状态：支持安全拒绝。

```sh
rmp --confirm=never /
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path`；never 只改变确认策略，不能绕过受保护路径检查。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (filesystem-root): Protected Path rejected: "/"
exit=3
结果: PASS（--confirm=never 不能绕过）
```

## TC-110：`--non-interactive` 不能绕过保护

状态：支持安全拒绝。

```sh
rmp --non-interactive /
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path`；非交互模式不能绕过受保护路径检查。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (filesystem-root): Protected Path rejected: "/"
exit=3
结果: PASS（--non-interactive 不能绕过）
```

## TC-111：root 执行不能被 force 绕过

状态：需要单独人工授权的环境测试；常规测试跳过。

```sh
printf root-safe > root-safe-file
sudo "$(command -v rmp)" -f "$PWD/root-safe-file"
printf 'exit=%s\n' "$?"
test -f root-safe-file && echo 'source=present'
```

预期退出码：3。stderr 包含 `root_execution` 和源路径；即使使用 `-f` 也在规划和 Trash 调用前拒绝，文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
结果: SKIP（状态：需要单独人工授权的环境测试；常规测试跳过；本轮不执行 sudo）
```

## TC-112：废纸篓同名目标由系统重命名

状态：支持。

```sh
printf first > collision-file
rmp collision-file
printf 'first-exit=%s\n' "$?"
printf second > collision-file
rmp collision-file
printf 'second-exit=%s\n' "$?"
test ! -e collision-file && echo 'source=absent'
```

预期：两个退出码均为 0。两次 stdout 都报告系统实际返回路径；第二次不得覆盖第一次，Finder 中可见两个项目，路径按系统规则区分。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
first: Moved "collision-file" to Trash at ".../collision-file". exit=0 内容 first
second: Moved "collision-file" to Trash at ".../collision-file 22-21-20-292". exit=0 内容 second
source=absent（两次移动后）
人工: 两项均放回原处成功
验证: TEST_DIR/collision-file=first；TEST_DIR/collision-file 22-21-20-292=second
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS（系统同名重命名，未覆盖）
```

## TC-113：空字符串路径

状态：支持失败。

```sh
rmp ""
printf 'exit=%s\n' "$?"
```

预期退出码：1。空字符串作为一个路径参数处理；stderr 包含 `missing_input` 和 `""`。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: missing_input: Trash Input does not exist: ""
exit=1
结果: PASS
```

## TC-114：force 忽略空字符串路径

状态：支持。

```sh
rmp -f ""
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 和 stderr 均为空；空字符串路径按 missing path 被忽略。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: 空
stderr: 空
exit=0
结果: PASS
```

## TC-115：重复原生短选项

状态：支持。

```sh
printf repeated-native > file-ffv
rmp -ffv file-ffv
printf 'exit=%s\n' "$?"
```

预期退出码：0。重复 `-f` 不产生错误，最终策略仍为 never 加 missing 忽略；`-v` 输出移动结果。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: Moved "file-ffv" to Trash at "/Users/virtualgemini/.Trash/file-ffv".
exit=0
source=absent（移动后）
人工: file-ffv 放回原处成功
验证: source=present 于 TEST_DIR/file-ffv；内容 repeated-native
残留: file-compat-x、file-quiet 21-12-05-525 仍在废纸篓
结果: PASS
```

## TC-116：dry-run 接受 `--stop-on-error`

状态：解析支持；成功计划中不产生可观察差异。

```sh
printf dry-stop-a > dry-stop-a
printf dry-stop-b > dry-stop-b
rmp --dry-run --stop-on-error dry-stop-a dry-stop-b
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 按顺序显示两个顶层对象；两个文件均保持原状。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout 按序:
Would move 2 items to Trash:
  [file] "dry-stop-a"
  [file] "dry-stop-b"
exit=0
两文件均仍在原处
结果: PASS
```

## TC-117：版本命令不能使用 `-a`

状态：支持拒绝。

```sh
rmp --version -a
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `-a is only valid with --help`；stdout 为空。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: -a is only valid with --help
exit=2
stdout: 空
结果: PASS
```

## TC-118：`--verbose --json`

状态：解析支持；JSON 执行暂不支持（10）。

```sh
printf verbose-json > file-verbose-json
rmp --verbose --json file-verbose-json
printf 'exit=%s\n' "$?"
test -f file-verbose-json && echo 'source=present'
```

预期退出码：2。stderr 包含 `unsupported_output_mode`。后面的 JSON 覆盖 verbose，文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported_output_mode for "file-verbose-json": JSON Trash Operation results are not available in this build
exit=2
source=present
结果: PASS（JSON 10 暂不支持）
```

## TC-119：`--quiet --json` 冲突

状态：支持拒绝。

```sh
printf quiet-json > file-quiet-json
rmp --quiet --json file-quiet-json
printf 'exit=%s\n' "$?"
test -f file-quiet-json && echo 'source=present'
```

预期退出码：2。stderr 包含 `conflicting options --json and --quiet`；选项顺序不改变冲突结果。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: conflicting options --json and --quiet
exit=2
source=present
结果: PASS
```

## TC-120：兼容选项 `-r` 位于严格模式之前

状态：支持拒绝。

```sh
printf strict-last-r > file-strict-last-r
rmp -r --strict-options file-strict-last-r
printf 'exit=%s\n' "$?"
test -f file-strict-last-r && echo 'source=present'
```

预期退出码：2。stderr 包含 `Compatibility Option -r is not allowed with --strict-options`；严格模式的位置不改变结果。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -r is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-121：兼容选项 `-R` 位于严格模式之前

状态：支持拒绝。

```sh
printf strict-last-R > file-strict-last-R
rmp -R --strict-options file-strict-last-R
printf 'exit=%s\n' "$?"
test -f file-strict-last-R && echo 'source=present'
```

预期退出码：2。stderr 包含 `Compatibility Option -R is not allowed with --strict-options`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -R is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-122：兼容选项 `-d` 位于严格模式之前

状态：支持拒绝。

```sh
printf strict-last-d > file-strict-last-d
rmp -d --strict-options file-strict-last-d
printf 'exit=%s\n' "$?"
test -f file-strict-last-d && echo 'source=present'
```

预期退出码：2。stderr 包含 `Compatibility Option -d is not allowed with --strict-options`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -d is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-123：兼容选项 `-x` 位于严格模式之前

状态：支持拒绝。

```sh
printf strict-last-x > file-strict-last-x
rmp -x --strict-options file-strict-last-x
printf 'exit=%s\n' "$?"
test -f file-strict-last-x && echo 'source=present'
```

预期退出码：2。stderr 包含 `Compatibility Option -x is not allowed with --strict-options`；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -x is not allowed with --strict-options
exit=2
source=present
结果: PASS
```

## TC-124：兼容选项 `-P` 位于严格模式之前

状态：支持拒绝。

```sh
printf strict-last-P > file-strict-last-P
rmp -P --strict-options file-strict-last-P
printf 'exit=%s\n' "$?"
test -f file-strict-last-P && echo 'source=present'
```

预期退出码：2。stderr 包含 `Compatibility Option -P is not allowed with --strict-options`，不输出普通 `-P` 警告；文件仍在原处。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: Compatibility Option -P is not allowed with --strict-options
exit=2
source=present（无普通 -P 警告）
结果: PASS
```

## TC-125：`-W` 位于严格模式之前

状态：支持拒绝。

```sh
printf strict-last-W > file-strict-last-W
rmp -W --strict-options file-strict-last-W
printf 'exit=%s\n' "$?"
test -f file-strict-last-W && echo 'source=present'
```

预期退出码：2。stderr 为 `unsupported Compatibility Option -W`；解析在 `-W` 处立即失败。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: unsupported Compatibility Option -W
exit=2
source=present
结果: PASS
```

## TC-126：版本与帮助冲突的反向顺序

状态：支持拒绝。

```sh
rmp --version --help
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 为 `rmp: --help and --version cannot be used together`；stdout 为空。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: --help and --version cannot be used together
exit=2
stdout: 空
结果: PASS
```

## TC-127：版本命令忽略附加路径

状态：支持。

```sh
rmp --version no-such-version-path
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 固定为 `rmp 0.1.0`；不存在的附加路径不会触发 `missing_input`，也不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout: rmp 0.1.0
exit=0
stderr: 无 missing_input
结果: PASS
```

## TC-128：根目录等价表达 `/./`

状态：支持安全拒绝。

```sh
rmp --dry-run /./
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (filesystem-root)`；不显示计划，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (filesystem-root): Protected Path rejected: "/./"
exit=3
结果: PASS
```

## TC-129：绝对路径中的父目录组件 `/tmp/..`

状态：当前实现允许 dry-run；不把绝对路径中的 `..` 直接归类为父目录表达式。

```sh
rmp --dry-run /tmp/..
printf 'exit=%s\n' "$?"
```

预期退出码：0。当前 macOS 上 `/tmp/..` 指向 `/private`，stdout 包含 `[directory] "/tmp/.."`。该用例明确记录当前边界，不能误写成根目录保护。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stdout:
Would move 1 item to Trash:
  [directory] "/tmp/.."
exit=0
结果: PASS（边界记录：非 parent-directory 保护）
```

## TC-130：当前目录表达 `./`

状态：支持安全拒绝。

```sh
rmp --dry-run ./
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (current-directory)`；不显示计划，不调用 Trash。

反馈：

```text
日期: 2026-07-14
TEST_DIR: /var/folders/l2/09xgvwr91sv001yj_ydqr6sh0000gn/T/tmp.tbyfgQFr3V
stderr: rmp: protected_path (current-directory): Protected Path rejected: "./"
exit=3
结果: PASS
```

## TC-131：当前目录绝对等价表达

状态：支持安全拒绝。

```sh
rmp --dry-run "$PWD/."
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (current-directory)`；不显示计划，不调用 Trash。

反馈：

```text

```

## TC-132：父目录表达式 `./..`

状态：支持安全拒绝。

```sh
rmp --dry-run ./..
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (parent-directory)`；不显示计划，不调用 Trash。

反馈：

```text

```

## TC-133：父目录表达式 `././..`

状态：支持安全拒绝。

```sh
rmp --dry-run ././..
printf 'exit=%s\n' "$?"
```

预期退出码：3。stderr 包含 `protected_path (parent-directory)`；不显示计划，不调用 Trash。

反馈：

```text

```

## TC-134：版本命令不能使用 `-zh`

状态：支持拒绝。

```sh
rmp --version -zh
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 包含 `-zh is only valid with --help`；stdout 为空。

反馈：

```text

```

## TC-135：目录默认真实执行

状态：目录识别支持；默认确认暂不支持（08）。

```sh
mkdir directory-default
rmp directory-default
printf 'exit=%s\n' "$?"
test -d directory-default && echo 'source=present'
```

预期退出码：1。默认 smart 策略要求确认；stderr 包含 `confirmation_required`，目录仍在原处。

反馈：

```text

```

## TC-136：无选项多对象真实执行

状态：暂不支持，09 完成前应安全失败。

```sh
printf plain-a > plain-batch-a
printf plain-b > plain-batch-b
rmp plain-batch-a plain-batch-b
printf 'exit=%s\n' "$?"
test -f plain-batch-a && test -f plain-batch-b && echo 'sources=present'
```

预期退出码：2。stderr 包含 `unsupported_input_count` 和两个源路径；两个文件都不移动。

反馈：

```text

```

## TC-137：`--dry-run` 缺少路径

状态：支持拒绝。

```sh
rmp --dry-run
printf 'exit=%s\n' "$?"
```

预期退出码：2。stderr 为 `rmp: at least one Trash Input is required`；不构造计划，不调用 Trash。

反馈：

```text

```

## TC-138：root 下的 dry-run

状态：需要单独人工授权的环境测试；当前实现只拒绝 root 的真实移动。

```sh
printf root-dry > root-dry-file
sudo "$(command -v rmp)" --dry-run "$PWD/root-dry-file"
printf 'exit=%s\n' "$?"
test -f root-dry-file && echo 'source=present'
```

预期退出码：0。stdout 显示一个 `[file]` 计划；dry-run 不调用 Trash，文件仍在原处。该用例记录当前实现边界，不代表 root 可真实移动。

反馈：

```text

```

## TC-139：系统 Trash 调用失败且源对象未变化

状态：生产命令无法安全、确定地人工强制系统调用失败；由受控自动化测试覆盖。

```sh
CLANG_MODULE_CACHE_PATH=/tmp/rmp-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/rmp-swiftpm-module-cache \
make test-unit
printf 'exit=%s\n' "$?"
```

预期退出码：0。测试输出包含 `System Trash failure exposes a stable code, source path, and honest status` 并通过；对应 CLI 分支返回退出码 1，stderr 包含 `trash_system_call_failed (not_moved)` 和源路径，不执行永久删除、覆写或自动补偿移动。

反馈：

```text

```

## TC-140：系统 Trash 调用失败后的状态无法确认

状态：生产命令无法安全、确定地人工构造；由受控自动化测试覆盖。

```sh
CLANG_MODULE_CACHE_PATH=/tmp/rmp-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/rmp-swiftpm-module-cache \
make test-unit
printf 'exit=%s\n' "$?"
```

预期退出码：0。测试输出包含 `CLI reports state_uncertain when a failed Trash call leaves no reliable source state` 并通过；该分支报告 `trash_system_call_failed (state_uncertain)`，不得声称成功或已回滚。

反馈：

```text

```

## TC-141：只有选项终止符

状态：支持拒绝。

```sh
rmp --
printf 'exit=%s\n' "$?"
```

预期退出码：2。`--` 只结束选项解析，不是路径；stderr 为 `rmp: at least one Trash Input is required`。

反馈：

```text

```

## TC-142：文件名本身为 `--`

状态：支持。

```sh
printf double-dash > ./--
rmp -- --
printf 'exit=%s\n' "$?"
test ! -e ./-- && echo 'source=absent'
```

预期退出码：0。第一个 `--` 结束选项解析，第二个 `--` 作为路径进入废纸篓。

反馈：

```text

```

## TC-143：帮助修饰符 `-a` 位于 `--help` 之前

状态：支持。

```sh
rmp -a --help
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 输出英文兼容帮助；修饰符和 `--help` 的先后顺序不改变帮助页面。

反馈：

```text

```

## TC-144：帮助修饰符 `-zh` 位于 `--help` 之前

状态：支持。

```sh
rmp -zh --help
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 输出中文主帮助；stderr 为空。

反馈：

```text

```

## TC-145：两个帮助修饰符都位于 `--help` 之前

状态：支持。

```sh
rmp -a -zh --help
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 输出中文兼容帮助；stderr 为空。

反馈：

```text

```

## TC-146：版本命令保留 `-P` 警告

状态：支持。

```sh
rmp --version -P
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 固定为 `rmp 0.1.0`；stderr 包含一次 `-P does not securely overwrite` 警告。

反馈：

```text

```

## TC-147：`-P` 后出现 `-W`

状态：支持拒绝。

```sh
printf P-W > file-P-W
rmp -P -W file-P-W
printf 'exit=%s\n' "$?"
test -f file-P-W && echo 'source=present'
```

预期退出码：2。stderr 只报告 `unsupported Compatibility Option -W`；解析失败时不会输出已累积的 `-P` 警告，文件仍在原处。

反馈：

```text

```

## TC-148：dry-run 忽略唯一的 missing path

状态：支持。

```sh
rmp --dry-run --ignore-missing missing-dry-only
printf 'exit=%s\n' "$?"
```

预期退出码：0。stdout 为 `Would move 0 items to Trash:`；stderr 为空，不调用 Trash。

反馈：

```text

```

## TC-149：dry-run 在多个输入中忽略 missing path

状态：支持。

```sh
printf present > dry-mixed-present
rmp --dry-run --ignore-missing dry-mixed-missing dry-mixed-present
printf 'exit=%s\n' "$?"
test -f dry-mixed-present && echo 'source=present'
```

预期退出码：0。stdout 只列出 `[file] "dry-mixed-present"`，不列出 missing path；现有文件保持原状。

反馈：

```text

```

## TC-150：受保护目录身份无法取得

状态：生产环境无法安全、确定地人工破坏这些系统身份；由受控自动化测试覆盖。

```sh
CLANG_MODULE_CACHE_PATH=/tmp/rmp-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/rmp-swiftpm-module-cache \
make test-unit
printf 'exit=%s\n' "$?"
```

预期退出码：0。测试输出包含 `Unavailable safety identity reports the escaped source path without Trash access` 并通过；对应 CLI 分支返回退出码 3，stderr 包含 `safety_identity_unavailable` 和源路径，Trash 调用次数为 0。

反馈：

```text

```

## TC-151：`-P` 与 dry-run 的输出通道

状态：支持。

```sh
printf P-dry > file-P-dry
rmp -P --dry-run file-P-dry > P-dry.stdout 2> P-dry.stderr
status=$?
printf 'exit=%s\n' "$status"
cat P-dry.stdout
cat P-dry.stderr
test -f file-P-dry && echo 'source=present'
```

预期退出码：0。stdout 只包含 `Would move 1 item to Trash:` 计划；stderr 只包含 `-P does not securely overwrite` 警告；文件仍在原处，警告不进入 Trash Plan。

反馈：

```text

```

## TC-152：多对象与 JSON 的错误优先级

状态：多对象真实执行暂不支持（09）；在 JSON 执行检查前安全失败。

```sh
printf json-batch-a > json-batch-a
printf json-batch-b > json-batch-b
rmp --json json-batch-a json-batch-b
printf 'exit=%s\n' "$?"
test -f json-batch-a && test -f json-batch-b && echo 'sources=present'
```

预期退出码：2。stderr 包含 `unsupported_input_count` 和两个源路径，不包含 `unsupported_output_mode`；两个文件都不移动。

反馈：

```text

```

## 测试安全边界

不要使用永久删除方式清理已验证对象。先在 Finder 中确认废纸篓和“放回原处”。工作区、HOME、根目录和系统目录不得作为真实移动目标。
