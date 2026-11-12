# NotepadPlus 2.7（Build 18）验证记录

日期：2026-11-05。

## 自动回归

- Swift Package：54 项测试通过，0 失败。包含已有搜索、替换、文件恢复保护，以及新增层级排序、旧分组兼容、无效父级及循环修复、禁止循环移动、Markdown 块行号映射、HTML 转义和视口数值钳制。
- WorkspaceStore 实际模型：7 项独立场景通过，使用临时文件与独立偏好域。验证三层分组重启恢复、阻止循环移动、删除父分组保留文档及子分组，以及无会话时从临时文档保险库恢复祖先链；旧文件权限与损坏会话保护回归保持通过。
- 原生 WebKit：4 项场景通过。验证页面脚本关闭时隔离应用脚本可用、复制全文／选区、源码行定位与预览滚动回传、原地更新正文／主题并保留视口。测试使用非持久化 WebKit 数据，不读取用户浏览数据。

运行入口：`swift test`、`bash Distribution/test-workspace.sh`、`bash Distribution/test-markdown-preview.sh`。受限环境中 Swift Package 可将 `CLANG_MODULE_CACHE_PATH` 和 `SWIFTPM_MODULECACHE_OVERRIDE` 指向 `/tmp`，使用独立 `--scratch-path`。WebKit 集成需要 macOS 图形会话和 WebKit 辅助进程权限。

## 应用界面

通过独立 Bundle ID `com.wanglp.notepadplus.qa27` 的测试副本检查，不修改正式应用的数据、分组、文档或文件授权。

- 查找及替换框均可快捷键粘贴，剪切板内容单次插入；修复广播编辑命令造成的重复粘贴。
- 预览选区复制按钮可复制渲染文字；编辑源码后预览标题更新，复制全文包含渲染后的标题和正文，不含标题／加粗标记。
- 源码与预览滚动到对应段落，预览切换为全文后仍保留阅读位置，返回双栏可继续编辑。
- 从父分组及二级分组的“…”菜单依次创建二级、三级分组，弹框自动显示对应完整父路径；新建文档进入选中的三级分组。
- Release 测试副本重启后，三层分组、文档归属和未保存正文恢复。

滚动同步按 Markdown 块与源行近似对应，长段落、代码及表格不保证逐像素一致。本机 GUI 验证在 Apple 芯片 Mac 完成，Intel 架构完成编译与镜像检查，未在 Intel 实机启动。

## 构建与安装包

Debug 及 arm64／x86_64 Universal Release 构建通过。此环境 Xcode 的集成 Swift 驱动在依赖计划阶段崩溃，构建时使用 `SWIFT_ENABLE_EXPLICIT_MODULES=NO SWIFT_USE_INTEGRATED_DRIVER=NO`；不改变应用沙盒配置。

打包脚本改用标准 DiskImages 流程，修复旧 `makehybrid` 生成器为镜像条目附加空 FinderInfo、导致包内签名严格校验失败的问题；新增自动只读挂载后核验签名、架构、版本及安装入口。

安装包校验包括：DMG CRC、SHA-256、镜像内正式 Bundle ID、2.7／18 版本、双架构、有效本地签名及沙盒授权项、`/Applications` 符号链接和当前版本日志。

本包使用 ad-hoc 本地签名，未进行 Developer ID 签名或 Apple 公证。文件访问授权跨版本的系统行为仍可能要求用户重新授权；保留 2.6.1 的恢复入口及备份机制，不保证已被旧版覆盖且无备份的数据可以重建。
