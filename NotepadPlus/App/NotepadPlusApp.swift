import SwiftUI
import UIKit

@main
struct NotepadPlusApp: App {
    @UIApplicationDelegateAdaptor(NotepadPlusAppDelegate.self) private var appDelegate
    @StateObject private var preferences: EditorPreferences
    @StateObject private var workspace: WorkspaceStore

    init() {
        let preferences = EditorPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        _workspace = StateObject(wrappedValue: WorkspaceStore(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            RootView(workspace: workspace, preferences: preferences)
                .onOpenURL { workspace.open(url: $0) }
                .environment(\.locale, Locale(identifier: "zh-Hans"))
        }
        .commands { AppFileEditCommands(preferences: preferences, workspace: workspace) }
        .commands { ViewPanelCommands(preferences: preferences) }
    }
}

@MainActor
enum DesktopMenu {
    static func send(_ command: DesktopCommand) {
        if case .native(let action) = command, action.performStandardEditAction() { return }
        NotificationCenter.default.post(name: .desktopCommand, object: command)
    }

    @ViewBuilder
    static func command(
        _ title: String,
        action: ShortcutAction,
        command: DesktopCommand,
        preferences: EditorPreferences
    ) -> some View {
        Button(title) { send(command) }
            .appKeyboardShortcut(preferences.shortcut(for: action))
    }
}

/// UIKit menu builder — Catalyst reliably shows menus inserted here.
final class NotepadPlusAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }

        let tools = UIMenu(
            title: "辅助工具",
            children: [
                UIAction(title: "函数列表") { _ in DesktopMenu.send(.showFunctionList) },
                UIAction(title: "命令面板…") { _ in DesktopMenu.send(.showCommandPalette) },
                UIAction(title: "搜索文件（全盘）…") { _ in DesktopMenu.send(.showFileSearch) },
                UIAction(title: "搜索代码片段…") { _ in DesktopMenu.send(.showSnippets) },
                UIAction(title: "新建代码片段…") { _ in DesktopMenu.send(.showCreateSnippet) },
                UIAction(title: "剪贴板历史…") { _ in DesktopMenu.send(.showClipboardHistory) },
                UIAction(title: "文档信息") { _ in DesktopMenu.send(.showDocumentInfo) },
                UIMenu(title: "JSON", children: [
                    UIAction(title: "JSONPath 查询") { _ in DesktopMenu.send(.showJSONPath) },
                    UIAction(title: "JSON 树视图") { _ in DesktopMenu.send(.showJSONTree) },
                    UIAction(title: "JSON 工具箱") { _ in DesktopMenu.send(.showJSONTools) },
                    UIAction(title: "JSON 错误定位") { _ in DesktopMenu.send(.validateJSON) },
                ]),
                UIMenu(title: "书签", children: [
                    UIAction(title: "切换书签") { _ in DesktopMenu.send(.toggleBookmark) },
                    UIAction(title: "下一个书签") { _ in DesktopMenu.send(.nextBookmark) },
                    UIAction(title: "上一个书签") { _ in DesktopMenu.send(.previousBookmark) },
                    UIAction(title: "打开书签面板") { _ in DesktopMenu.send(.showBookmarksPanel) },
                ]),
                UIAction(title: "配置工具栏…") { _ in DesktopMenu.send(.customizeToolbar) },
                UIAction(title: "打开辅助功能设置…") { _ in
                    NotificationCenter.default.post(name: .openAccessibilitySettings, object: nil)
                },
            ]
        )
        // Insert after View (显示). Fall back to before Window if needed.
        if builder.menu(for: .view) != nil {
            builder.insertSibling(tools, afterMenu: .view)
        } else {
            builder.insertSibling(tools, beforeMenu: .window)
        }
    }
}

private struct AppFileEditCommands: Commands {
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var workspace: WorkspaceStore

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("关于 NotepadPlus") { DesktopMenu.send(.showAbout) }
            Button("版本更新记录…") { DesktopMenu.send(.showReleaseNotes) }
        }

        CommandGroup(replacing: .appSettings) {
            Button("偏好设置…") { DesktopMenu.send(.openPreferences) }
                .keyboardShortcut(",", modifiers: .command)
            DesktopMenu.command("快捷键管理…", action: .openShortcutManager, command: .openShortcutManager, preferences: preferences)
            Button("配置工具栏…") { DesktopMenu.send(.customizeToolbar) }
        }

        CommandGroup(replacing: .newItem) {
            DesktopMenu.command("新建文档", action: .newDocument, command: .newDocument, preferences: preferences)
            Button("新建文档分组…") { DesktopMenu.send(.newDocumentGroup) }
            DesktopMenu.command("打开…", action: .openDocument, command: .openDocument, preferences: preferences)
            Button("打开文件夹工作区…") { DesktopMenu.send(.openWorkspace) }
            Button("快速打开文件…") { DesktopMenu.send(.quickOpen) }
                .keyboardShortcut("p", modifiers: .command)
            Button("搜索文件…") { DesktopMenu.send(.showFileSearch) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            if workspace.recentFiles.isEmpty {
                Button("最近使用：没有文件") {}.disabled(true)
            } else {
                ForEach(workspace.recentFiles, id: \.path) { url in
                    Button("打开最近使用：\(url.lastPathComponent)") {
                        workspace.open(url: url)
                    }
                    .help(url.path)
                }
                Button("清除最近使用") { workspace.clearRecentFiles() }
            }
            Divider()
            Button("关闭当前文档") { DesktopMenu.send(.closeActiveDocument) }
            Button("关闭所有未修改文档") { DesktopMenu.send(.closeUnchangedDocuments) }
        }

        CommandGroup(replacing: .saveItem) {
            DesktopMenu.command("保存", action: .saveDocument, command: .saveDocument, preferences: preferences)
            DesktopMenu.command("另存为…", action: .saveAs, command: .saveAsDocument, preferences: preferences)
            DesktopMenu.command("全部保存", action: .saveAll, command: .saveAll, preferences: preferences)
        }

        CommandGroup(replacing: .undoRedo) {
            DesktopMenu.command("撤销", action: .undo, command: .native(.undo), preferences: preferences)
            DesktopMenu.command("重做", action: .redo, command: .native(.redo), preferences: preferences)
        }

        CommandGroup(replacing: .pasteboard) {
            DesktopMenu.command("剪切", action: .cut, command: .native(.cut), preferences: preferences)
            DesktopMenu.command("复制", action: .copy, command: .native(.copy), preferences: preferences)
            DesktopMenu.command("粘贴", action: .paste, command: .native(.paste), preferences: preferences)
            DesktopMenu.command("全选", action: .selectAll, command: .native(.selectAll), preferences: preferences)
            DesktopMenu.command("选择下一个匹配项", action: .selectNextOccurrence, command: .native(.selectNextOccurrence), preferences: preferences)
        }

        CommandGroup(after: .textEditing) {
            Menu("行操作") {
                DesktopMenu.command("复制行", action: .duplicateLine, command: .editLine(.duplicate), preferences: preferences)
                DesktopMenu.command("删除行", action: .deleteLine, command: .editLine(.delete), preferences: preferences)
                DesktopMenu.command("上移行", action: .moveLineUp, command: .editLine(.moveUp), preferences: preferences)
                DesktopMenu.command("下移行", action: .moveLineDown, command: .editLine(.moveDown), preferences: preferences)
                DesktopMenu.command("切换注释", action: .toggleComment, command: .editLine(.toggleComment), preferences: preferences)
                DesktopMenu.command("缩进", action: .indent, command: .editLine(.indent), preferences: preferences)
                DesktopMenu.command("反缩进", action: .outdent, command: .editLine(.outdent), preferences: preferences)
                Button("合并行") { DesktopMenu.send(.editLine(.joinWithNext)) }
                Button("删除空行") { DesktopMenu.send(.editLine(.removeEmptyLines)) }
            }
            Menu("文本转换") {
                ForEach(TextTransformation.allCases) { transformation in
                    Button(preferences.title(for: transformation)) {
                        DesktopMenu.send(.transformText(transformation))
                    }
                }
            }
            Divider()
            Button("命令面板…") { DesktopMenu.send(.showCommandPalette) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }
    }
}

private struct ViewPanelCommands: Commands {
    @ObservedObject var preferences: EditorPreferences

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("函数列表") { DesktopMenu.send(.showFunctionList) }
            Button("书签面板") { DesktopMenu.send(.showBookmarksPanel) }
            Button("文档信息") { DesktopMenu.send(.showDocumentInfo) }
            Button("搜索文件（全盘）…") { DesktopMenu.send(.showFileSearch) }
            Button("搜索代码片段…") { DesktopMenu.send(.showSnippets) }
            Button("剪贴板历史…") { DesktopMenu.send(.showClipboardHistory) }
            Menu("底部面板") {
                Button("函数列表") { DesktopMenu.send(.showFunctionList) }
                Button("书签面板") { DesktopMenu.send(.showBookmarksPanel) }
                Button("文档信息") { DesktopMenu.send(.showDocumentInfo) }
                Button("在文件中查找") { DesktopMenu.send(.findInFiles) }
                Divider()
                Button("JSONPath 查询") { DesktopMenu.send(.showJSONPath) }
                Button("JSON 树视图") { DesktopMenu.send(.showJSONTree) }
                Button("JSON 工具箱") { DesktopMenu.send(.showJSONTools) }
            }
            Divider()
            DesktopMenu.command("列模式", action: .toggleColumnMode, command: .toggleColumnMode, preferences: preferences)
            DesktopMenu.command("切换分栏编辑", action: .toggleSplitEditor, command: .toggleSplit, preferences: preferences)
            DesktopMenu.command("Markdown 预览", action: .markdownPreview, command: .toggleMarkdownPreview, preferences: preferences)
            Divider()
            DesktopMenu.command("放大字体", action: .zoomIn, command: .zoom(1), preferences: preferences)
            DesktopMenu.command("缩小字体", action: .zoomOut, command: .zoom(-1), preferences: preferences)
            DesktopMenu.command("重置缩放", action: .resetZoom, command: .zoom(0), preferences: preferences)
            Divider()
            DesktopMenu.command("下一个标签页", action: .nextTab, command: .nextTab, preferences: preferences)
            DesktopMenu.command("上一个标签页", action: .previousTab, command: .previousTab, preferences: preferences)
            DesktopMenu.command("复制标签页", action: .duplicateTab, command: .duplicateActiveDocument, preferences: preferences)
            Button("按名称排列标签页") { DesktopMenu.send(.sortDocumentsByName) }
            Divider()
            Toggle("自动换行", isOn: $preferences.wordWrap)
            Toggle("显示行号", isOn: $preferences.showLineNumbers)
            Toggle("显示空白字符", isOn: $preferences.showWhitespace)
        }

        CommandGroup(after: .sidebar) {
            Button("显示或隐藏文档导航栏") { DesktopMenu.send(.toggleSidebar) }
        }
    }
}
