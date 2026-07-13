# macos-rm-plus 产品需求文档

Status: Draft

Target release: v0.1.0

Platform: macOS 13 及以上

License: Apache-2.0

## 1. 产品概述

`macos-rm-plus` 是一个面向 macOS 的安全删除命令行工具，通过 `rmp` 命令调用。它接受用户熟悉的 `rm` 风格调用，但不会直接永久删除文件，而是通过 macOS 系统废纸篓 API 将文件或目录移入废纸篓。

产品采用以下核心策略：

> 宽容解析，精简语义；兼容常见调用形式，但不继承与废纸篓模型无关的实现负担。

`rmp` 不是 `/bin/rm` 的完全等价替代品。它提供参数层面的迁移便利，但有意改变删除结果：对象进入系统废纸篓，并尽可能保留 Finder 支持的“放回原处”能力。

## 2. 背景与问题

传统永久删除命令存在以下体验和安全问题：

- 删除结果通常无法直接恢复。
- 删除目录需要理解 `-r`、`-R` 或 `-d` 等历史参数。
- `-f` 同时承载“不确认”和“忽略不存在”等多重含义。
- `-i` 在批量场景中产生大量逐项确认，`-I` 的触发规则又不直观。
- 递归删除大型目录需要遍历并逐项删除整个层级。
- 缺少原生的 dry-run、结构化结果和明确的批处理策略。
- Agent 和已有脚本经常生成 `rm -rf`，完全拒绝这些参数会降低迁移可用性。

macOS 已提供系统废纸篓 API，因此 `rmp` 无需复制传统递归删除器的实现。它应围绕操作计划、安全策略、系统废纸篓服务和确定性输出重新设计。

## 3. 产品目标

### 3.1 主要目标

1. 将文件和目录交给 macOS 系统废纸篓处理，不自行模拟 `~/.Trash` 移动。
2. 默认不执行永久删除，也不在废纸篓失败后静默回退到永久删除。
3. 让最常见操作保持简单：`rmp <path>...` 同时支持文件和目录。
4. 接受常见 `rm` 风格参数组合，使 `rmp -rf path` 等调用不会因冗余参数失败。
5. 只在主界面暴露对废纸篓操作有实际价值的选项。
6. 为人类、脚本和 Agent 提供稳定的退出码、非交互模式和结构化输出。
7. 对根目录、用户主目录、当前工作目录和提权执行提供不可被 `-f` 绕过的安全保护。

### 3.2 成功标准

- 所有成功操作都通过系统废纸篓 API 完成。
- 代码中不存在“废纸篓失败后永久删除”的执行路径。
- `rmp file` 和 `rmp directory` 均无需递归参数即可工作。
- `rmp -rf path`、`rmp -Rfv path` 和 `rmp -- -filename` 能被正确解析。
- 无意义的兼容参数不会进入执行层或触发递归遍历。
- 未知参数、危险的语义降级和不支持的替代操作不会被静默接受。
- 主帮助保持简洁，并将兼容参数说明放在独立帮助页。

## 4. 非目标

v0.1.0 不包括：

- 替换或修改系统 `/bin/rm`。
- 保证与传统永久删除命令完全相同的文件系统结果。
- 安全覆写、介质擦除或敏感数据销毁。
- 在废纸篓不可用时自动永久删除。
- 操作系统私有废纸篓元数据或 Finder 私有数据库。
- 清空废纸篓。
- Linux、Windows 或其他平台支持。
- GUI、菜单栏应用或 Finder 扩展。
- 自有的 `undo`、`history`、`restore` 子命令；这些属于后续版本。
- 完整复刻任何既有实现的错误文本、内部结构或非公开边界行为。

## 5. 目标用户

### 5.1 交互式终端用户

希望降低误删风险，同时保留熟悉的命令行使用方式。

### 5.2 脚本作者

需要确定性退出码、可预测的批处理行为以及不阻塞的非交互执行方式。

### 5.3 编程 Agent

可能生成常见的 `rm -rf` 调用，需要宽容的参数解析、dry-run、JSON 结果和明确的安全失败。

## 6. 产品原则

### 6.1 Trash only

默认且唯一的删除行为是移入系统废纸篓。失败即失败，不进行破坏性降级。

### 6.2 Parse broadly, execute narrowly

解析层可以识别历史兼容参数，但执行层只接收与废纸篓操作相关的领域模型。

### 6.3 Safety cannot be forced away

`-f` 只能控制确认和不存在路径的处理，不能关闭根目录保护、用户主目录保护、当前目录保护、提权保护或永久删除禁令。

### 6.4 No unnecessary traversal

目录作为顶层对象整体交给系统 API，不为模拟 `-r` 而递归扫描、统计或逐项移动。

### 6.5 Deterministic automation

相同参数必须产生相同策略。程序不得根据调用者是否为 Agent 来改变语义。

## 7. 核心用户体验

### 7.1 基本操作

```shell
rmp report.txt
rmp build
rmp report.txt build output
```

文件和目录使用相同调用方式，不要求 `-r`。

### 7.2 兼容调用

```shell
rmp -rf build
rmp -Rfv build dist
rmp -- -filename
```

`-r`、`-R` 和 `-d` 只在兼容解析层出现，不触发递归遍历。

### 7.3 Dry run

```shell
rmp --dry-run build report.txt
```

输出顶层操作计划，不递归统计目录内容：

```text
Would move 2 items to Trash:
  [directory] "build"
  [file] "report.txt"
```

Paths are rendered as quoted strings. Control characters such as newlines are escaped so every
top-level Trash Input remains a single unambiguous output line, while ordinary Unicode and spaces
are preserved.

### 7.4 批量确认

```shell
rmp --confirm=once build dist report.txt
```

```text
Move 3 items, including 2 directories, to Trash? [y/N]
```

### 7.5 机器输出

```shell
rmp --json --non-interactive --confirm=never build
```

```json
{
  "operation": "trash",
  "success": true,
  "moved": 1,
  "failed": 0,
  "items": [
    {
      "source": "/project/build",
      "destination": "/Users/example/.Trash/build",
      "status": "moved"
    }
  ]
}
```

## 8. 命令行规格

### 8.1 主命令

```text
rmp [OPTIONS] <PATH>...
```

至少需要一个路径。路径参数在 Shell 展开后逐个作为顶层对象处理。

### 8.2 原生选项

| 选项 | 语义 |
| --- | --- |
| `-f`, `--force` | 不确认，并忽略不存在的路径；不能绕过安全保护 |
| `-i`, `--interactive` | 每个顶层项目操作前确认 |
| `-I` | 当顶层参数超过 3 个或包含目录时，整批确认一次 |
| `-v`, `--verbose` | 输出每个顶层项目的结果 |
| `--confirm=<mode>` | `smart`、`never`、`once` 或 `each` |
| `--ignore-missing` | 忽略不存在的路径，但不改变确认策略 |
| `--dry-run` | 输出计划但不执行任何移动 |
| `--non-interactive` | 禁止读取终端；若当前策略需要确认则失败 |
| `--quiet` | 不输出正常结果；错误仍写入 stderr |
| `--json` | 以稳定 JSON 结构输出完整结果 |
| `--stop-on-error` | 第一个顶层项目失败后停止处理后续项目 |
| `--strict-options` | 将无意义兼容参数视为用法错误 |
| `--help` | 显示精简的主帮助 |
| `--version` | 显示版本信息 |
| `--` | 结束选项解析 |

v0.1.0 的版本输出固定为 `rmp 0.1.0`。帮助与版本命令在进入路径检查或系统废纸篓能力前完成。

### 8.3 兼容选项

| 选项 | 默认模式 | 严格模式 | 说明 |
| --- | --- | --- | --- |
| `-r`, `-R` | 接受并静默忽略 | 报错 | 目录整体进入废纸篓，不递归遍历 |
| `-d` | 接受并静默忽略 | 报错 | 默认已经允许目录 |
| `-x` | 接受并静默忽略 | 报错 | 不存在用户态递归跨卷过程 |
| `-P` | 接受并向 stderr 警告 | 报错 | 不执行安全覆写；不得静默制造擦除预期 |
| `-W` | 报错 | 报错 | 表示不同操作意图，不能作为无操作参数处理 |

兼容参数不在主帮助的选项列表中。用户可以运行：

```shell
rmp --help -a
```

提供帮助列表的中文解释选项参数：

```shell
rmp --help -zh
rmp --help -a -zh
```

查看完整说明。

### 8.4 选项覆盖规则

参数必须单次、从左到右解析。

- 对兼容短参数，后出现的 `-f`、`-i` 覆盖之前的交互与 missing-path 策略。
- `-f` 设置确认模式为 `never`，并启用 ignore-missing。
- `-i` 设置确认模式为 `each`，并关闭由早先 `-f` 启用的兼容 ignore-missing。
- `-I` 设置兼容的条件式 once 策略。
- 显式长选项按出现顺序覆盖对应字段，但不修改无关字段。
- `--ignore-missing` 只影响不存在路径处理。
- `--confirm` 只影响确认策略。
- `--json` 与 `--quiet` 同时出现时返回用法错误，避免产生“既要求完整输出又要求无输出”的歧义。
- `--verbose` 与 `--json` 同时出现时不改变 JSON schema；JSON 本身始终包含全部顶层项目结果。
- 未知选项必须返回用法错误，不能被当作路径。

### 8.5 组合短选项

必须支持：

```shell
-rf
-Rfv
-fi
-if
```

组合内部仍按字符出现顺序处理，因此 `-fi` 和 `-if` 结果不同。

## 9. 确认策略

### 9.1 `smart`

默认确认模式为 `smart`：

- 一个普通文件：不确认。
- 多个顶层项目：确认一次。
- 任意顶层项目是目录：确认一次。
- 涉及用户主目录：作为受保护路径拒绝。
- 涉及受保护路径：拒绝，不以确认替代保护。
- stdin 不是 TTY 且需要确认：失败，不阻塞等待输入。

`smart` 只检查顶层对象，不递归计算目录内文件数或总大小。

### 9.2 `never`

不提示，但所有不可绕过安全策略继续生效。

### 9.3 `once`

执行前展示顶层项目摘要并确认一次。

### 9.4 `each`

按输入顺序对每个顶层项目确认。拒绝一个项目不阻止处理后续项目，除非启用 `--stop-on-error`。

## 10. 安全需求

### 10.1 系统废纸篓 API

FR-SAFE-001：所有实际移动必须通过 Foundation `FileManager.trashItem(at:resultingItemURL:)` 完成。

FR-SAFE-002：不得直接拼接或移动到 `~/.Trash`。

FR-SAFE-003：必须使用系统返回的最终废纸篓 URL，因为重名时目标名称可能变化。

### 10.2 禁止永久删除回退

FR-SAFE-004：系统废纸篓 API 失败时，原路径必须保持未被 rmp 永久删除。

FR-SAFE-005：v0.1.0 不提供隐藏、实验性或环境变量控制的永久删除回退。

### 10.3 受保护路径

FR-SAFE-006：必须拒绝文件系统根目录及其等价表达，例如 `/`、`//`、`/tmp/..`。

FR-SAFE-007：必须拒绝 `.`、`..` 以及与当前工作目录具有相同文件身份的目标。

FR-SAFE-008：必须拒绝用户主目录及其等价表达；v0.1.0 不提供绕过选项。

FR-SAFE-009：`-f`、`--confirm=never` 和 `--non-interactive` 不得绕过受保护路径检查。

FR-SAFE-010：符号链接保护必须作用于路径条目本身。指向受保护目标的符号链接可以被移入废纸篓，但不得因此移动链接目标。

### 10.4 提权执行

FR-SAFE-011：检测到有效用户 ID 为 0 时，默认拒绝执行实际移动，并解释 root 废纸篓和所有权风险。

FR-SAFE-012：v0.1.0 不提供绕过 root 拒绝的选项；后续版本需单独评审。

### 10.5 路径处理

FR-SAFE-013：不得对最终路径组件调用符号链接解析后再执行移动。

FR-SAFE-014：路径规范化必须保留“移动符号链接本身”的语义。

FR-SAFE-015：必须正确处理空格、Unicode、换行、前导连字符和长路径。

## 11. 执行模型

### 11.1 操作计划

参数解析后必须生成与历史参数解耦的领域对象：

```swift
struct TrashPlan {
    var inputs: [TrashInput]
    var confirmation: ConfirmationMode
    var ignoreMissing: Bool
    var output: OutputMode
    var dryRun: Bool
    var stopOnError: Bool
    var strictOptions: Bool
}
```

执行层不得包含 `recursive`、`directoryFlag`、`oneFileSystem` 或 `secureOverwrite` 等无实际语义的布尔字段。

### 11.2 处理顺序

FR-EXEC-001：顶层项目必须按照命令行输入顺序串行处理。

FR-EXEC-002：默认情况下，一个项目失败后继续处理后续项目。

FR-EXEC-003：启用 `--stop-on-error` 后，第一个失败结束剩余处理。

FR-EXEC-004：批量操作不宣称具备事务性；中断或错误可能造成部分成功。

FR-EXEC-005：不得为了进度、确认或摘要递归扫描目录。

### 11.3 不存在路径

FR-EXEC-006：默认将不存在路径视为失败。

FR-EXEC-007：启用 ignore-missing 后，不存在路径不输出错误，也不导致非零退出码。

### 11.4 废纸篓失败

以下情况均作为普通失败报告，不做破坏性回退：

- 卷不支持废纸篓。
- 网络文件系统行为不支持系统移动。
- TCC 或文件权限拒绝。
- 外接卷只读或不可用。
- File Provider 项目无法完成操作。

## 12. 输出与退出码

### 12.1 输出通道

- 正常人类输出写入 stdout。
- 警告和错误写入 stderr。
- `--json` 模式下，stdout 只包含一个完整 JSON 文档。
- `--quiet` 不抑制 stderr 错误。

### 12.2 默认输出

成功且未启用 verbose 时，输出最终摘要：

```text
Moved 3 items to Trash; 1 failed.
```

单个成功操作可以保持安静；是否显示摘要由实现阶段的可用性测试最终确定，但必须在同一版本内保持一致。

### 12.3 退出码

| 退出码 | 含义 |
| --- | --- |
| `0` | 所有需要处理的项目成功，或失败仅为被忽略的 missing path |
| `1` | 至少一个项目操作失败或用户拒绝确认 |
| `2` | 命令行用法、未知选项或不支持选项错误 |
| `3` | 安全策略拒绝，例如受保护路径或 root 执行 |

退出码在 v1.0 前可以扩展，但不得在补丁版本中改变既有含义。

## 13. JSON 输出契约

顶层结构：

```json
{
  "schemaVersion": 1,
  "operation": "trash",
  "dryRun": false,
  "success": false,
  "moved": 1,
  "failed": 1,
  "skipped": 0,
  "items": []
}
```

每个项目至少包含：

```json
{
  "source": "/absolute/input/path",
  "destination": "/absolute/trash/path-or-null",
  "kind": "file|directory|symlink|other|unknown",
  "status": "planned|moved|failed|skipped",
  "error": {
    "code": "trash_unavailable",
    "message": "Human-readable message"
  }
}
```

`error` 在无错误时为 `null`。机器消费者应依赖稳定的 `code`，不应解析 `message`。

## 14. 帮助信息

### 14.1 主帮助

主帮助只展示：

- 基本用法。
- 核心安全承诺。
- 原生选项。
- 三个最常见示例。
- 指向 `rmp --help -a` 的说明。

目标是常规终端高度下无需滚动或只需少量滚动。

### 14.2 兼容帮助

兼容帮助必须明确区分：

- 接受但无效果的参数。
- 接受但产生警告的参数。
- 明确不支持的参数。

不得将 `-P` 描述为安全删除，不得暗示 `-W` 已执行。

## 15. Finder 恢复能力

FR-RESTORE-001：产品文档只能表述为“使用 macOS 系统废纸篓 API，以保留 Finder 支持的恢复能力”。

FR-RESTORE-002：不得承诺所有情况下都能“放回原处”。以下情况可能导致恢复失败：

- 原父目录已不存在。
- 原位置出现同名对象。
- 原卷未挂载。
- 项目已从废纸篓清空。
- 用户在废纸篓中重命名或移动了项目。
- 网络卷或 File Provider 有不同实现。

## 16. 性能要求

- 不递归扫描目录作为删除前置步骤。
- 不计算目录总文件数或总字节数，除非未来通过显式 `--estimate` 请求。
- 顶层对象串行处理，优先保证顺序和可预测性。
- 对 10,000 个顶层路径的参数解析不得产生与目录内容规模相关的复杂度。
- verbose 输出属于显式成本；默认摘要不得逐项打印全部成功结果。

## 17. 测试要求

### 17.1 测试隔离与禁止事项

测试体系本身属于高风险面。测试代码、错误的 fixture、路径规范化缺陷或误用 release binary 都可能造成真实数据损失。项目采用固定目录白名单作为真实文件系统测试的安全边界。

#### 17.1.1 固定测试根目录

FR-TEST-001：测试目录采用双重固定目录。外层容器和唯一授权的真实测试根目录分别为：

```text
~/rmp-test
~/rmp-test/test
```

`~/rmp-test` 只是不可操作的安全容器；只有 `~/rmp-test/test` 内符合规则的后代路径可以用于真实测试。主目录必须通过可信的系统账户信息或 `FileManager.homeDirectoryForCurrentUser` 取得，不能直接信任可被调用者修改的 `HOME` 环境变量。

FR-TEST-002：如果 `~/rmp-test` 或 `~/rmp-test/test` 不存在，测试启动器可以依次创建同名目录；两个目录的权限都必须为 `0700`。创建必须使用不跟随符号链接且不覆盖既有对象的原子语义。

FR-TEST-003：如果任一目录已经存在，必须分别通过 `lstat` 或等价的不跟随符号链接检查，确认 `~/rmp-test` 和 `~/rmp-test/test` 都是当前用户拥有的真实目录。以下任一情况必须拒绝测试：

- 路径是符号链接。
- 路径不是目录。
- 所有者不是当前有效用户。
- 目录权限不是 `0700`，即任何组用户或其他用户权限位不为零。
- 无法可靠取得目录文件身份。

FR-TEST-004：外层容器必须包含 `.rmp-test-container` marker，授权测试根目录必须包含 `.rmp-test-root` marker。Marker 只用于证明“该目录被明确准备为测试目录”，不作为目录身份的唯一可信来源。

Marker 必须满足：

- 是当前用户拥有的普通文件。
- 不是符号链接。
- 权限为 `0600`。
- 使用不跟随符号链接且不覆盖既有对象的 exclusive create 语义创建。
- 至少包含格式版本、目录角色和创建时的目录 device/inode。
- 已存在 marker 不得被 truncate、重写或静默修复；内容不合法时直接拒绝测试。

FR-TEST-005：每次测试运行必须在 `~/rmp-test/test/<run-uuid>/` 下以 exclusive create 语义创建全新的独立运行目录，并创建包含同一 UUID 的 `.rmp-test-run` marker。运行目录或 marker 已存在时必须失败，不得复用。所有测试 fixture 只能位于该运行目录的后代路径中。

FR-TEST-006：不得将 `~/rmp-test`、`~/rmp-test/test` 或当前 `<run-uuid>` 运行目录本身作为 rmp 的目标；测试目录和文件必须创建在运行目录的下一层或更深位置。

#### 17.1.2 白名单执行规则

FR-TEST-007：测试模式下，任何会检查、计划或移动路径的 rmp 操作都必须先验证目标位于当前授权的 `<run-uuid>` 目录内。路径位于白名单之外时必须立即拒绝，不能进入确认或废纸篓调用阶段。

FR-TEST-008：白名单判断不能使用简单字符串前缀。例如 `/Users/me/rmp-test-evil` 不能被视为 `/Users/me/rmp-test` 的后代；`~/rmp-test/other` 即使位于外层容器中，也不属于 `~/rmp-test/test` 白名单。

FR-TEST-009：白名单判断必须规范化中间路径组件、验证目录文件身份并拒绝通过中间符号链接逃逸。最终路径组件如果是符号链接，可以作为目录项本身进行测试，但不得跟随到白名单外目标。

FR-TEST-010：白名单校验必须至少执行两次：

1. 生成 `TrashPlan` 前。
2. `TrashClient` 调用系统废纸篓 API前。

第二次校验用于降低计划生成后路径被替换所产生的竞态风险。

FR-TEST-011：测试不得使用 `sudo`、root 用户、Full Disk Access 或放宽 TCC 权限。

FR-TEST-012：禁止在测试中向真实 rmp 可执行文件传入 `/`、根目录等价路径、用户主目录、当前工作目录或系统目录。上述输入只能传给 fake filesystem 下的参数解析器和安全策略单元测试。

FR-TEST-013：`--help`、`--version` 和不接受路径的纯信息命令不受目录白名单限制。

FR-TEST-014：真实文件系统测试必须使用单独的测试构建产物 `rmp-test`。该产物必须通过编译期 `RMP_TESTING` 配置启用白名单，不能通过环境变量把生产 `rmp` 动态切换为测试模式。

FR-TEST-015：`rmp-test` 必须硬编码白名单结构 `~/rmp-test/test/<run-uuid>/`，启动时输出或暴露可验证的测试构建标识。所有接受路径的测试调用必须提供测试专用的 `--test-run-id <uuid>`；该选项只存在于 `RMP_TESTING` 构建中，生产 `rmp` 不得识别。测试启动器必须在执行前断言：

- 当前产物名称和构建标识为 `rmp-test`。
- `RMP_TESTING` 编译配置存在。
- 当前有效用户不是 root。
- 当前 run UUID 与 `.rmp-test-run` marker 一致。

任一条件不满足时，测试进程必须在解析路径参数前退出。

FR-TEST-016：真实 Foundation 实现不得在测试代码中直接构造。测试构建只能通过 `WhitelistedTrashClient` 获得系统废纸篓能力；其构造函数必须接收已经验证的测试安全上下文，并在每次调用前再次执行白名单校验。

FR-TEST-017：测试安全上下文必须在启动时记录 `~/rmp-test`、`~/rmp-test/test` 和 `<run-uuid>` 三层目录的 device/inode，并在每次真实系统调用前重新比较。目录身份变化时立即拒绝。

FR-TEST-018：文件系统集成测试必须串行执行。当前运行期间不得启动会重命名、替换或重新挂载测试根目录及其祖先路径的后台任务。

FR-TEST-019：由于 Foundation 废纸篓 API最终仍基于路径调用，即使进行两次校验和目录身份比较，也不能宣称完全消除最终检查与调用之间的 TOCTOU 风险。该风险通过 `0700` 权限、单用户测试、串行执行、目录文件描述符和调用前身份复核共同降低。

FR-TEST-020：测试启动器应打开并在整个运行期间保留外层容器、测试根目录和运行目录的目录文件描述符。中间路径检查应尽量使用相对于已打开目录描述符且不跟随符号链接的方式完成。

FR-TEST-021：所有真实测试目标必须与当前 `<run-uuid>` 目录位于同一 volume。目标或任一中间目录是挂载点、跨卷入口、网络卷或 File Provider 特殊根时必须拒绝本地集成测试。

FR-TEST-022：测试 fixture 的 basename 必须包含 `rmp-test-<run-uuid>-` 前缀，以避免与用户废纸篓中的既有项目混淆。

FR-TEST-023：系统返回的废纸篓 URL 位于白名单之外，只允许用于只读验证和发布前 Finder 恢复验证。验证时必须同时比较系统返回的 URL、run UUID 前缀和可用的文件资源标识符。

FR-TEST-024：本地测试不得对系统返回的废纸篓 URL调用永久删除 API，也不得按文件名搜索并清理废纸篓。自动清理真实废纸篓项目只允许在一次性托管 macOS runner 中，并且仍须验证精确返回 URL和文件资源标识符。

FR-TEST-025：测试使用 spy/fake trash client 时必须记录系统能力调用次数和收到的 URL。所有路径拒绝、marker 失败、权限失败、卷边界失败和符号链接逃逸测试必须断言调用次数为零。

FR-TEST-026：本地测试完成后，测试启动器只允许在重新验证 run UUID、marker 和运行目录 device/inode 后，删除 `.rmp-test-run` marker 并使用非递归 `rmdir` 删除已经为空的运行目录。运行目录仍包含任何其他项目时必须保留现场并报告，不得执行递归清理。

FR-TEST-027：测试启动器永远不得自动删除 `~/rmp-test/test`、`.rmp-test-root`、`~/rmp-test` 或 `.rmp-test-container`。这些长期安全边界只能由用户显式、手工处理。

#### 17.1.3 断言与不可省略的安全检查

测试代码应尽量使用断言尽早暴露违反安全边界的状态，包括：

- 外层容器或授权测试根目录的文件身份不符合预期。
- marker 或 run UUID 不匹配。
- fixture 路径不在运行目录内。
- fake trash client 收到白名单外路径。
- 真实 TrashClient wrapper 收到未经验证的计划。

但是 `assert` 不能作为唯一安全控制，因为优化构建可能移除断言。每一个断言都必须对应不可省略的运行时检查：

```swift
assert(isInsideAuthorizedTestRoot(url))

guard isInsideAuthorizedTestRoot(url) else {
    throw TestSafetyError.pathOutsideWhitelist(url)
}
```

生产模式和测试模式必须在构建配置或依赖注入边界上明确区分。生产版本不得包含通过环境变量启用、关闭或改变测试白名单的后门。

### 17.2 参数解析测试

必须覆盖：

- `-rf`、`-Rfv`、`-fi`、`-if`。
- 重复和相互覆盖的确认选项。
- `--` 和以连字符开头的路径。
- 未知选项。
- `-P` 警告与严格模式。
- `-W` 拒绝。
- 原生长选项和兼容短选项混合顺序。

### 17.3 文件系统集成测试

文件系统集成测试只能在 17.1 规定的 `~/rmp-test/test/<run-uuid>/` 白名单内运行。必须覆盖：

- 普通文件和目录。
- 空目录和深层目录。
- 符号链接与断开的符号链接。
- 指向受保护路径的符号链接。
- 只读文件和权限错误。
- 不存在路径与 ignore-missing。
- Unicode、空格、换行和前导连字符文件名。
- 同名废纸篓目标导致的系统重命名。
- 多个项目的部分成功。
- dry-run 不产生文件系统修改。
- 白名单外路径在调用系统废纸篓 API前被拒绝。
- `~/rmp-test` 或 `~/rmp-test/test` 被替换为符号链接时测试启动器拒绝运行。
- `~/rmp-test/other` 等外层容器内但不在 `test` 子目录中的路径被拒绝。
- 中间目录被替换为指向白名单外的符号链接时操作被拒绝。
- 外层容器、测试根目录或运行目录的 device/inode 在运行中变化时操作被拒绝。
- 目标或中间目录跨卷、成为挂载点或进入 File Provider 特殊根时操作被拒绝。
- 测试误调用生产 `rmp` 或缺少 `RMP_TESTING` 构建标识时，在路径解析前失败。
- 缺少、格式错误或与 marker 不匹配的 `--test-run-id` 在路径解析前失败。
- 所有真实 fixture 名称包含当前 run UUID 前缀。
- 本地测试只读验证系统返回的废纸篓 URL，不执行自动永久清理。
- 本地运行目录只有在为空且身份复核通过时才能通过非递归 `rmdir` 清理。

### 17.4 安全测试

- 所有根目录等价路径均被拒绝。
- 用户主目录及其等价路径均被拒绝。
- 当前工作目录及其等价路径均被拒绝。
- `-f` 不能绕过保护。
- root 执行被拒绝。
- 废纸篓失败不会调用永久删除 API。
- 在 fake filesystem 中验证 `/`、`//`、`/tmp/..` 等输入，不在宿主机调用真实可执行文件。
- 注入路径越界、marker 缺失、run UUID 不匹配和中间符号链接逃逸时，测试适配器在任何系统 API 调用前拒绝执行。
- 对每一种安全拒绝场景断言 spy trash client 的调用次数为零。
- Marker 是符号链接、非普通文件、权限不是 `0600` 或内容损坏时拒绝测试。
- 已存在的 `<run-uuid>` 目录和 `.rmp-test-run` marker 不得被复用。

### 17.5 手工验证

- 手工验证使用 `~/rmp-test/test/<run-uuid>/` 中创建的专用 fixture，不得使用真实用户文件。
- Finder 能看到由 rmp 移入的项目。
- 在正常本地卷场景下，对系统返回的精确 URL验证 Finder“放回原处”；操作前核对 run UUID 前缀和文件资源标识符。
- 外接卷、iCloud/File Provider 和网络卷作为兼容性矩阵记录结果，不将所有场景设为发布阻塞项。

## 18. 可观测性与隐私

- v0.1.0 不收集遥测。
- 默认不保存用户删除路径历史。
- 错误日志不得上传或发送到外部服务。
- JSON 输出可能包含绝对路径，由调用者负责保护输出内容。

## 19. 发布与分发

- 使用 Swift Package Manager 构建。
- 提供 Apple Silicon 和 Intel 架构支持；发布形式可为 universal binary 或分别构建。
- 首选 GitHub Releases 与 Homebrew 分发。
- 发布二进制应使用 Developer ID 签名并进行 Apple notarization。
- 安装不得覆盖 `/bin/rm`，也不得自动修改用户 shell 配置。
- README 可以给出用户自愿设置 alias/function 的示例，并明确脚本语义差异。

## 20. 许可证与贡献

- 项目源码与发布产物采用 Apache-2.0。
- 原创源码使用 `SPDX-License-Identifier: Apache-2.0`。
- 贡献指南要求贡献者只提交其有权贡献的原创或许可证兼容内容。
- 推荐采用 DCO `Signed-off-by` 流程。
- 仓库不提交研究用手册原文或上游源码副本。

## 21. 风险与缓解措施

### 21.1 用户误认为是永久删除

缓解：命令名保持为 `rmp`；帮助和 README 明确写“Move to Trash”；不宣称完全等价替代。

### 21.2 脚本用于释放磁盘空间

移动到废纸篓通常不会立即释放空间。缓解：文档明确说明；不提供静默清空废纸篓或永久删除回退。

### 21.3 无意义参数掩盖用户意图

缓解：仅对确实冗余的 `-r/-R/-d/-x` 静默接受；`-P` 警告；`-W` 和未知参数报错；提供严格模式。

### 21.4 系统废纸篓行为跨卷不同

缓解：完全依赖系统 API，并将不支持情况作为可诊断失败返回。

### 21.5 大规模 verbose 输出

缓解：默认摘要；只有显式 verbose 才逐项输出。

### 21.6 交互阻塞自动化

缓解：非 TTY 时需要确认则失败；提供 `--non-interactive`、`--confirm=never` 和 JSON 输出。

### 21.7 测试误操作损害宿主系统

安全测试的目标路径本身可能是根目录、主目录或系统目录。如果直接在开发者本机执行，即使预期安全策略会拒绝，也可能因待测代码回归而造成不可恢复的系统损害。

缓解：使用编译期隔离的 `rmp-test` 专用产物和不可绕过的 `WhitelistedTrashClient`；`~/rmp-test` 只作为不可操作的外层容器，真实文件系统测试只授权 `~/rmp-test/test/<run-uuid>/`；三层目录均记录并复核 device/inode；使用严格权限、marker、run UUID、卷边界检查和两层白名单校验；危险路径只通过 fake filesystem 验证；本地测试不得自动清理真实废纸篓；断言用于尽早发现问题，但每个断言必须同时具备不可被优化移除的运行时拒绝逻辑。

## 22. 分阶段路线图

### v0.1.0：可靠的系统废纸篓命令

- 基本文件和目录移动。
- 兼容参数解析。
- 安全保护。
- dry-run。
- 人类输出和 JSON 输出。
- 串行批处理与稳定退出码。

### v0.2.0：批量输入和操作记录

- `--stdin0`。
- `--files-from` / `--files0-from`。
- 可选的本地操作日志。
- 进程中断后的更清晰恢复提示。

### v0.3.0：历史与撤销

- `rmp history`。
- `rmp undo --last`。
- `rmp restore <operation-id>`。
- 原路径冲突策略。
- 废纸篓项目已变化或缺失时的诊断。

历史与撤销不得依赖 Finder 私有数据库，必须只使用 rmp 自己在操作时记录的数据和公开文件系统能力。

## 23. v0.1.0 发布验收标准

满足以下全部条件才可发布：

1. 所有实际删除路径均调用系统废纸篓 API。
2. 代码审查确认不存在永久删除回退。
3. 参数兼容测试矩阵全部通过。
4. 根目录、主目录、当前目录、符号链接和 root 执行安全测试在规定的 fake filesystem 或 `~/rmp-test/test/<run-uuid>/` 白名单环境中通过。
5. dry-run 测试证明零文件系统变更。
6. JSON schema 有固定版本并通过快照测试。
7. Finder 本地卷手工恢复验证通过。
8. 主帮助、兼容帮助和 README 对无意义参数及语义差异说明一致。
9. Intel 与 Apple Silicon 构建通过。
10. LICENSE、NOTICE 和贡献政策与 Apache-2.0 要求一致。
11. CI 和本地集成测试都只能修改 `~/rmp-test/test/<run-uuid>/` 内由当前测试创建的 fixture；`~/rmp-test`、`~/rmp-test/test` 和运行目录本身均不可作为 rmp 目标。
12. 测试安全包络的路径越界、marker 缺失、run UUID 不匹配、权限不安全和符号链接逃逸测试全部通过。
13. 代码审查确认没有任何真实测试向 rmp 传入 `/`、用户主目录、当前工作目录或系统目录。
14. 所有真实文件系统测试只调用带 `RMP_TESTING` 编译标识的 `rmp-test`，且无法直接构造未包装的 Foundation TrashClient。
15. 三层目录身份变化、挂载点、跨卷路径和 File Provider 特殊根测试全部在系统废纸篓 API调用前失败。
16. 所有安全拒绝测试都断言 trash client 调用次数为零。
17. 本地测试不存在对系统废纸篓目标调用永久删除 API的代码路径。
18. 本地测试清理只能删除已验证且为空的 run 目录，不能递归清理或删除两层固定安全目录。

## 24. 待实现阶段验证的决策

以下项目不阻塞 PRD，但必须在实现对应功能前确定：

- 单个成功操作默认完全静默，还是输出一行摘要。
- `-P` 警告是否在非 TTY 环境默认显示。
- JSON 中是否包含 Foundation 原始错误域和错误码。
- 最低 macOS 版本是否需要低于 macOS 13。
- Homebrew 首版采用源码构建还是预编译 bottle。
