// SPDX-License-Identifier: Apache-2.0

enum InformationRenderer {
  static let version = "rmp 0.1.0\n"

  static func render(_ page: HelpPage) -> String {
    switch page {
    case .primaryEnglish: primaryEnglish
    case .compatibilityEnglish: compatibilityEnglish
    case .primaryChinese: primaryChinese
    case .compatibilityChinese: compatibilityChinese
    }
  }

  private static let primaryEnglish = """
    Usage: rmp [OPTIONS] <PATH>...

    Move files and directories to the macOS system Trash. rmp never falls back to permanent
    deletion,
    and force options cannot bypass Protected Path checks.

    Native options:
      -f, --force             Never confirm and ignore missing paths
      -i, --interactive       Confirm each top-level Trash Input
      -I                       Confirm once for a large or directory-containing operation
      -v, --verbose           Report every top-level result
          --confirm=<MODE>    smart, never, once, or each
          --ignore-missing    Ignore missing paths only
          --dry-run           Print the Trash Plan without moving anything
          --non-interactive   Never read from the terminal
          --quiet             Suppress normal output
          --json              Emit the complete result as JSON
          --stop-on-error     Stop after the first failed Trash Input
          --strict-options    Reject no-effect Compatibility Options
          --help              Show this help
          --version           Show version information
      --                       End option parsing

    Examples:
      rmp report.txt
      rmp --dry-run build report.txt
      rmp -- -leading-hyphen

    Run 'rmp --help -a' for Compatibility Option details.
    """

  private static let compatibilityEnglish = """
    rmp Compatibility Options

    Accepted with no effect:
      -r, -R, -d, -x   Directories are moved as top-level items without recursive traversal.

    Accepted with a warning:
      -P               Secure overwrite is not performed; the item is only moved to Trash.

    Unsupported:
      -W               This requests a different operation and is rejected.

    --strict-options rejects every no-effect Compatibility Option, including -P.
    """

  private static let primaryChinese = """
    用法：rmp [选项] <路径>...

    将文件和目录移入 macOS 系统废纸篓。rmp 不会降级为永久删除，强制选项也不能绕过受保护路径检查。

    原生选项：
      -f, --force             不确认并忽略不存在的路径
      -i, --interactive       逐个确认顶层废纸篓输入
      -I                       对较大批次或包含目录的操作确认一次
      -v, --verbose           输出每个顶层结果
          --confirm=<模式>    smart、never、once 或 each
          --ignore-missing    仅忽略不存在的路径
          --dry-run           输出废纸篓计划但不移动任何项目
          --non-interactive   禁止读取终端
          --quiet             抑制正常输出
          --json              输出完整 JSON 结果
          --stop-on-error     首次失败后停止
          --strict-options    拒绝无效果的兼容选项
          --help              显示帮助
          --version           显示版本
      --                       结束选项解析

    示例：
      rmp report.txt
      rmp --dry-run build report.txt
      rmp -- -leading-hyphen

    运行 'rmp --help -a -zh' 查看兼容选项说明。
    """

  private static let compatibilityChinese = """
    rmp 兼容选项

    接受但无效果：
      -r, -R, -d, -x   目录作为顶层项目整体移动，不执行递归遍历。

    接受但会警告：
      -P               不执行安全覆写；项目只会移入废纸篓。

    不支持：
      -W               该选项表示不同操作意图，因此拒绝。

    --strict-options 会拒绝所有无效果的兼容选项，包括 -P。
    """
}
