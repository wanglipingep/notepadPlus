# NotepadPlus 2.6.1（Build 17）验证记录

2026-10-27。修复对象为升级后分组／文件记录丢失及外部文件授权失败。

已确认的代码问题：启动读取外部文件失败时使用 `compactMap` 丢弃记录；会话与最近文件反复生成授权书签，失败的空值会覆盖旧书签；旧会话整体解码失败后仍可能创建并保存新会话。2.6 DMG 为临时签名，其指定要求包含代码哈希，跨版本授权兼容性存在风险。未取得反馈用户的原始会话，不能将签名风险认定为该用户分组消失的唯一原因。

验证结果：

- `swift test`：45 项测试通过，包含 7 项新增会话迁移／备份／损坏恢复回归。
- `bash Distribution/test-workspace.sh`：5 项工作区回归场景通过；编译实际 WorkspaceStore、EditorDocument 与核心源码，仅替换 UIKit 相关界面协作者。覆盖不可访问文件保留、原书签保留、文件夹恢复、重启、取消／误选、真实文件权限拒绝和损坏会话防覆盖。使用独立 UserDefaults suite 和临时文件，未修改正式应用数据。
- Catalyst Debug 与 Universal Release 构建通过。Release 包含 arm64 和 x86_64。
- 验证 DMG CRC、SHA256、镜像内应用签名、版本／Bundle ID、可执行文件权限、沙盒授权项、当前 CHANGELOG 与 `/Applications` 符号链接。
- 验证打包已有签名的应用时保留原指定要求，未强制重签为临时签名。

验证边界：本地模型回归没有模拟 macOS 对旧版本沙盒授权的批准，系统文件／文件夹选择器与真实受影响用户机器上的恢复仍需现场确认。当前 DMG 使用临时签名，未进行 Developer ID 签名／公证，后续升级仍可能要求重新授权。旧版已覆盖且没有备份的数据无法保证恢复。

会话备份目录为应用 Application Support 下的 `NotepadPlus/WorkspaceSession/`，包含当前会话、上一版本和首次迁移原始副本；损坏原始数据另存为 `session.unreadable-*.json`。请保留正式应用数据与系统备份，避免卸载清理数据。
