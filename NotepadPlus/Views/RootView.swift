import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// One opaque surface for window chrome and navigation, shared by UIKit and
/// SwiftUI so translucency cannot create different colours above each column.
enum EditorChrome {
    static var uiBackground: UIColor { .secondarySystemBackground }
    static var background: Color { Color(uiColor: uiBackground) }
}

private struct ChineseToolbarTipModifier: ViewModifier {
    let text: String

    @State private var isHovering = false
    @State private var hoverToken = UUID()
    @State private var tipID = UUID()

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: ToolbarTipAnchorKey.self, value: .bounds) { [tipID: $0] }
            .onHover { hovering in
                isHovering = hovering
                let token = UUID()
                hoverToken = token
                if hovering {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        guard isHovering, hoverToken == token else { return }
                        NotificationCenter.default.post(
                            name: .toolbarTipChanged,
                            object: ToolbarTipEvent(id: tipID, text: text, isPresented: true)
                        )
                    }
                } else {
                    NotificationCenter.default.post(
                        name: .toolbarTipChanged,
                        object: ToolbarTipEvent(id: tipID, text: text, isPresented: false)
                    )
                }
            }
            .onDisappear {
                isHovering = false
                hoverToken = UUID()
                NotificationCenter.default.post(
                    name: .toolbarTipChanged,
                    object: ToolbarTipEvent(id: tipID, text: text, isPresented: false)
                )
            }
            .accessibilityHint(text)
    }
}

private struct ToolbarTipEvent {
    let id: UUID
    let text: String
    let isPresented: Bool
}

private struct ToolbarTipAnchorKey: PreferenceKey {
    static let defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ToolbarTipOverlay: View {
    let anchors: [UUID: Anchor<CGRect>]
    let event: ToolbarTipEvent?

    var body: some View {
        GeometryReader { geometry in
            if let event, let anchor = anchors[event.id] {
                let bounds = geometry[anchor]
                let width = min(max(110, CGFloat(event.text.count) * 13 + 24), min(400, geometry.size.width - 16))
                Text(event.text)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                    .offset(
                        x: max(8, min(bounds.midX - width / 2, geometry.size.width - width - 8)),
                        y: bounds.maxY + 6
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    func toolbarTip(_ text: String) -> some View {
        modifier(ChineseToolbarTipModifier(text: text))
    }
}

struct RootView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isImporterPresented = false
    @State private var isFolderImporterPresented = false
    @State private var isExporterPresented = false
    @State private var isSettingsPresented = false
    @State private var isShortcutManagerPresented = false
    @State private var isAboutPresented = false
    @State private var isReleaseNotesPresented = false
    @State private var isInstallReminderPresented = false
    @State private var isCommandPalettePresented = false
    @State private var isQuickOpenPresented = false
    @State private var isFileSearchPresented = false
    @State private var isSnippetsPresented = false
    @State private var snippetsEntryMode: SnippetsEntryMode = .search
    @State private var isClipboardHistoryPresented = false
    @State private var isToolbarCustomizationPresented = false
    @State private var exportPayload: ExportTextDocument?
    @State private var exportingDocumentID: UUID?
    @State private var closeAfterExport = false
    @State private var documentPendingClose: EditorDocument?
    @State private var showCloseConfirmation = false
    @State private var isGoToLinePresented = false
    @State private var toolbarTip: ToolbarTipEvent?

    var body: some View {
        rootWithNotifications
    }

    private var rootSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 340)
        } detail: {
            ZStack {
                VStack(spacing: 0) {
                    editorCommandBar
                        .zIndex(10)
                    Group {
                        if let document = workspace.activeDocument {
                            EditorScreen(
                                document: document,
                                workspace: workspace,
                                preferences: preferences
                            )
                        } else {
                            ContentUnavailableView(
                                preferences.tr("没有打开的文档", "No Document"),
                                systemImage: "doc.text",
                                description: Text(preferences.tr("新建或打开文本文件即可开始。", "Create or open a text file to begin."))
                            )
                        }
                    }
                }
                fileSearchFloatingOverlay
                snippetsFloatingOverlay
                clipboardFloatingOverlay
                settingsFloatingOverlay
            }
            #if targetEnvironment(macCatalyst)
            .background(DetailOriginReporter())
            .onPreferenceChange(DetailOriginKey.self) { TitlebarQuoteLayout.setDetailMinX($0) }
            .onChange(of: columnVisibility) { _, visibility in
                if visibility == .detailOnly {
                    TitlebarQuoteLayout.setDetailMinX(0)
                }
            }
            #endif
            .toolbar(.hidden, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .animation(.easeOut(duration: 0.12), value: toolbarTip?.id)
        .tint(preferences.themeForegroundColor)
        .background(EditorChrome.background)
        .preferredColorScheme(preferences.preferredColorScheme)
        .onAppear(perform: handleRootAppear)
        #if targetEnvironment(macCatalyst)
        .background(TitlebarQuoteBridge(preferences: preferences))
        #endif
    }

    private var rootWithImporters: some View {
        rootSplitView
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    workspace.open(urls: urls)
                case .failure(let error):
                    workspace.errorMessage = preferences.tr(
                        "打开文件失败：\(error.localizedDescription)",
                        "Could not open files: \(error.localizedDescription)"
                    )
                }
            }
            .fileImporter(
                isPresented: $isFolderImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let folder = urls.first { workspace.openWorkspace(url: folder) }
                case .failure(let error):
                    workspace.errorMessage = preferences.tr(
                        "打开文件夹失败：\(error.localizedDescription)",
                        "Could not open folder: \(error.localizedDescription)"
                    )
                }
            }
            .fileExporter(
                isPresented: $isExporterPresented,
                document: exportPayload,
                contentType: .plainText,
                defaultFilename: exportDefaultFilename
            ) { result in
                completeExport(result)
            }
            .fileImporter(
                isPresented: $workspace.isFileAccessImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { workspace.completeFileAccess($0, folder: false) }
            .fileImporter(
                isPresented: $workspace.isFolderAccessImporterPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { workspace.completeFileAccess($0, folder: true) }
    }

    private var rootWithSheets: some View {
        rootWithImporters
            .sheet(isPresented: $isShortcutManagerPresented) {
                NavigationStack {
                    ShortcutManagerView(preferences: preferences)
                }
                .frame(minWidth: 720, minHeight: 680)
            }
            .sheet(isPresented: $isAboutPresented) {
                AboutNotepadPlusView()
            }
            .sheet(isPresented: $isReleaseNotesPresented) {
                ReleaseNotesView()
            }
            .sheet(isPresented: $isGoToLinePresented) {
                if let document = workspace.activeDocument {
                    GoToLineSheet(document: document, preferences: preferences, isPresented: $isGoToLinePresented)
                }
            }
            .sheet(isPresented: $isCommandPalettePresented) {
                CommandPaletteView(workspace: workspace, preferences: preferences) { command in
                    isCommandPalettePresented = false
                    DispatchQueue.main.async { handle(command) }
                }
            }
            .sheet(isPresented: $isQuickOpenPresented) {
                QuickOpenView(workspace: workspace, preferences: preferences) {
                    isQuickOpenPresented = false
                }
            }
        .sheet(isPresented: $isToolbarCustomizationPresented) {
                ToolbarCustomizationView(preferences: preferences)
                    .frame(minWidth: 520, idealWidth: 600, minHeight: 520, idealHeight: 620)
            }
    }

    private var rootWithAlerts: some View {
        rootWithSheets
            .alert(
                "NotepadPlus",
                isPresented: errorIsPresented,
                actions: {
                    if workspace.fileAccessRecoveryURL != nil {
                        Button(preferences.tr("重新选择文件…", "Select File Again…")) {
                            DispatchQueue.main.async { workspace.requestFileAccess() }
                        }
                        Button(preferences.tr("授权所在文件夹…", "Authorize Containing Folder…")) {
                            DispatchQueue.main.async { workspace.requestFileAccess(folder: true) }
                        }
                    }
                    Button(preferences.tr("确定", "OK")) { workspace.errorMessage = nil }
                },
                message: {
                    Text(workspace.errorMessage ?? preferences.tr("未知错误", "Unknown error"))
                }
            )
            .alert(item: $workspace.externalFileChange) { change in
                externalFileChangeAlert(for: change)
            }
            .alert(
                preferences.tr("建议先安装 NotepadPlus", "Install NotepadPlus"),
                isPresented: $isInstallReminderPresented
            ) {
                Button(preferences.tr("打开应用程序文件夹", "Open Applications Folder")) {
                    #if targetEnvironment(macCatalyst)
                    UIApplication.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
                    #endif
                }
                Button(preferences.tr("稍后", "Later"), role: .cancel) {}
            } message: {
                Text(preferences.tr(
                    "当前正在从磁盘映像运行。请先将 NotepadPlus 拖入“应用程序”文件夹，再从应用程序中启动。",
                    "NotepadPlus is running from a disk image. Drag it to the Applications folder, then launch it from there."
                ))
            }
            .confirmationDialog(
                preferences.tr(
                    "是否保存对 \(documentPendingClose?.title ?? "文档") 的更改？",
                    "Save changes to \(documentPendingClose?.title ?? "document")?"
                ),
                isPresented: $showCloseConfirmation,
                titleVisibility: .visible
            ) {
                Button(preferences.tr("保存并关闭", "Save and Close")) {
                    if let documentPendingClose {
                        save(documentPendingClose, closeAfterSaving: true)
                    }
                }
                Button(preferences.tr("不保存并关闭", "Close Without Saving"), role: .destructive) {
                    if let documentPendingClose {
                        workspace.close(documentPendingClose)
                    }
                    documentPendingClose = nil
                }
                Button(preferences.tr("取消", "Cancel"), role: .cancel) {
                    documentPendingClose = nil
                }
            }
    }

    private var rootWithNotifications: some View {
        rootWithAlerts
            .onReceive(NotificationCenter.default.publisher(for: .requestCloseDocument)) { notification in
                guard let document = notification.object as? EditorDocument else { return }
                requestClose(document)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSnippetsGlobalHotKey)) { _ in
                openSnippetsFromGlobalHotKey()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openAccessibilitySettings)) { _ in
                openAccessibilitySettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .desktopCommand)) { notification in
                guard let command = notification.object as? DesktopCommand else { return }
                handle(command)
            }
            .onReceive(NotificationCenter.default.publisher(for: .searchAllRequested)) { notification in
                guard let request = notification.object as? SearchAllRequest else { return }
                workspace.workspaceSearchQuery = request.query
                workspace.workspaceSearchOptions = request.options
                workspace.workspaceSearchScope = request.scope
                workspace.searchWorkspace(in: request.range)
            }
            .onReceive(NotificationCenter.default.publisher(for: .markAllSearchRequested)) { notification in
                guard let request = notification.object as? MarkAllRequest,
                      let document = workspace.activeDocument else { return }
                workspace.workspaceSearchQuery = request.query
                workspace.workspaceSearchOptions = request.options
                workspace.markAllSearchMatches(in: document, range: request.range)
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearSearchMarksRequested)) { _ in
                workspace.clearSearchMarks(in: workspace.activeDocument)
            }
            .onReceive(NotificationCenter.default.publisher(for: .toolbarTipChanged)) { notification in
                guard let event = notification.object as? ToolbarTipEvent else { return }
                if event.isPresented {
                    toolbarTip = event
                } else if toolbarTip?.id == event.id {
                    toolbarTip = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                toolbarTip = nil
                workspace.flushPendingChanges()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                workspace.flushPendingChanges()
            }
    }

    private func handleRootAppear() {
        columnVisibility = .all
        KeyboardShortcutMonitor.shared.configure(preferences: preferences) { action in
            performShortcutAction(action)
        }
        ClipboardHistoryStore.shared.startMonitoring()
        SystemSnippetBridge.startFrontmostTracking()
        presentInstallReminderIfNeeded()
        installSnippetGlobalHotKey()
    }

    private func presentInstallReminderIfNeeded() {
        #if targetEnvironment(macCatalyst)
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        guard bundlePath.hasPrefix("/Volumes/"),
              !UserDefaults.standard.bool(forKey: "notepad-plus.install-reminder-shown.v1")
        else { return }

        UserDefaults.standard.set(true, forKey: "notepad-plus.install-reminder-shown.v1")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isInstallReminderPresented = true
        }
        #endif
    }

    private var editorCommandBar: some View {
        HStack(spacing: 10) {
            commandBarGroup {
                Button {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                } label: {
                    Image(systemName: columnVisibility == .detailOnly ? "sidebar.leading" : "sidebar.left")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(columnVisibility == .detailOnly ? "显示文档导航栏" : "隐藏文档导航栏")
                .toolbarTip(columnVisibility == .detailOnly ? "显示文档导航栏" : "隐藏文档导航栏")

                commandBarDivider

            Button {
                workspace.newDocument()
            } label: {
                Image(systemName: "doc.badge.plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("新建文档", "New document"))
            .toolbarTip("新建文档（\(preferences.shortcut(for: .newDocument).display)）")

            Menu {
                Button(preferences.tr("打开文件…", "Open Files…")) {
                    isImporterPresented = true
                }
                Button(preferences.tr("打开文件夹工作区…", "Open Folder as Workspace…")) {
                    isFolderImporterPresented = true
                }
            } label: {
                Image(systemName: "folder")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(preferences.tr("打开文件", "Open files"))
            .toolbarTip("打开文件或工作区（\(preferences.shortcut(for: .openDocument).display)）")

            Button(action: saveActiveDocument) {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("保存", "Save"))
            .toolbarTip("保存当前文档（\(preferences.shortcut(for: .saveDocument).display)）")

            Button(action: saveAllDocuments) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("全部保存", "Save all"))
            .toolbarTip("保存全部文档（\(preferences.shortcut(for: .saveAll).display)）")
        }

            Spacer(minLength: 8)

            documentCommandBarTitle

            Spacer(minLength: 8)

            commandBarGroup {
                ForEach(preferences.toolbarItems) { item in
                    toolbarButton(for: item)
                }
                helpersAndMoreMenu
            }

            // The configurable toolbar above replaces this legacy fixed group.
            // Keep the implementation for compatibility without rendering it twice.
            /* Legacy toolbar menu retained below for reference; the configurable
               toolbar above replaces this block. */
            /* if false { commandBarGroup {
                ForEach(preferences.toolbarItems) { item in
                    toolbarButton(for: item)
                }
                Menu {
                    Button("配置工具栏…") { isToolbarCustomizationPresented = true }
                    Button("恢复默认工具栏") { preferences.resetToolbarItems() }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("配置工具栏")
                .toolbarTip("配置右上角工具顺序和显示项目")
            }

            commandBarGroup {
            Menu {
                ForEach(EditorPreferences.editorFonts, id: \.self) { fontName in
                    Button {
                        preferences.fontName = fontName
                    } label: {
                        if preferences.fontName == fontName {
                            Label(fontDisplayName(fontName), systemImage: "checkmark")
                        } else {
                            Text(fontDisplayName(fontName))
                        }
                    }
                }
            } label: {
                Label(fontDisplayName(preferences.fontName), systemImage: "textformat")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .frame(maxWidth: 112)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("编辑器字体：\(fontDisplayName(preferences.fontName))")
            .toolbarTip("选择编辑器字体")

            Button {
                preferences.fontSize = max(9, preferences.fontSize - 1)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("缩小字体")
            .toolbarTip("缩小字体（\(preferences.shortcut(for: .zoomOut).display)）")

            Menu {
                ForEach([10, 12, 14, 15, 16, 18, 20, 24, 28, 32, 36, 40], id: \.self) { size in
                    Button("\(size) 磅") { preferences.fontSize = Double(size) }
                }
            } label: {
                Text("\(Int(preferences.fontSize)) 磅")
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 52)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("字体大小：\(Int(preferences.fontSize)) 磅")
            .toolbarTip("选择字体大小")

            Button {
                preferences.fontSize = min(40, preferences.fontSize + 1)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("放大字体")
            .toolbarTip("放大字体（\(preferences.shortcut(for: .zoomIn).display)）")
            }

            if false { commandBarGroup {

            Button {
                toggleColumnMode()
            } label: {
                Image(systemName: preferences.columnMode ? "rectangle.split.3x1.fill" : "rectangle.split.3x1")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(preferences.columnMode ? .green : .primary)
            .accessibilityLabel(preferences.columnMode ? "关闭列模式" : "开启列模式")
            .toolbarTip(preferences.columnMode
                ? "列模式已开启：直接拖动创建矩形选区；支持输入、粘贴和删除（\(preferences.shortcut(for: .toggleColumnMode).display)）"
                : "开启列模式（\(preferences.shortcut(for: .toggleColumnMode).display)）；也可按住 Option 拖动临时使用")

            Button {
                workspace.isFindBarPresented.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("查找与替换", "Find and replace"))
            .toolbarTip("查找与替换，支持正则表达式（\(preferences.shortcut(for: .find).display)）")

            Button {
                workspace.showBottomPanel(.search)
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("在文件中查找", "Find in files"))
            .toolbarTip("在工作区文件中查找和替换（\(preferences.shortcut(for: .findInFiles).display)）")

            Button {
                if let document = workspace.activeDocument {
                    workspace.toggleBookmark(in: document)
                }
            } label: {
                Image(systemName: workspace.activeDocument?.bookmarks.contains(
                    workspace.activeDocument?.currentLine ?? 0
                ) == true ? "bookmark.fill" : "bookmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("切换书签", "Toggle bookmark"))
            .toolbarTip("切换当前行书签（\(preferences.shortcut(for: .toggleBookmark).display)）")

            Button {
                workspace.toggleSplitEditor()
            } label: {
                Image(systemName: workspace.isSplitEditorPresented
                      ? "rectangle.split.2x1.fill"
                      : "rectangle.split.2x1")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("切换分栏编辑", "Toggle split editor"))
            .toolbarTip("切换左右分栏编辑（\(preferences.shortcut(for: .toggleSplitEditor).display)）")

            Button {
                workspace.isMarkdownPreviewPresented.toggle()
            } label: {
                Image(systemName: workspace.isMarkdownPreviewPresented
                      ? "rectangle.righthalf.inset.filled"
                      : "text.document")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preferences.tr("切换 Markdown 预览", "Toggle Markdown preview"))
            .toolbarTip("切换 Markdown 实时预览（\(preferences.shortcut(for: .markdownPreview).display)）")

            Menu {
                Button(preferences.tr("另存为…", "Save As…")) {
                    if let document = workspace.activeDocument { beginExport(document) }
                }
                .appKeyboardShortcut(preferences.shortcut(for: .saveAs))

                Button(preferences.tr("复制标签页", "Duplicate Tab")) {
                    workspace.duplicateActiveDocument()
                }
                .appKeyboardShortcut(preferences.shortcut(for: .duplicateTab))

                Button(preferences.tr("按名称排列标签页", "Sort Tabs by Name")) {
                    workspace.sortDocumentsByName()
                }

                Button(preferences.tr("关闭所有未修改标签页", "Close All Unchanged Tabs")) {
                    workspace.closeUnchangedDocuments()
                }

                Divider()

                Button(preferences.tr("跳转到行…", "Go to Line…")) {
                    isGoToLinePresented = true
                }

                Button(preferences.tr("切换书签", "Toggle Bookmark")) {
                    if let document = workspace.activeDocument {
                        workspace.toggleBookmark(in: document)
                    }
                }

                Button(preferences.tr("下一个书签", "Next Bookmark")) {
                    workspace.activeDocument?.goToAdjacentBookmark(forward: true)
                }

                Button(preferences.tr("格式化 JSON", "Format JSON")) {
                    handle(.native(.formatJSON))
                }
                .disabled(workspace.activeDocument?.language != .json
                    && workspace.activeDocument?.language != .jsonc)

                Button(preferences.tr("删除当前 JSON 值", "Delete JSON Value")) {
                    handle(.native(.deleteJSONValue))
                }
                .disabled(workspace.activeDocument?.language != .json
                    && workspace.activeDocument?.language != .jsonc)

                Button(preferences.tr("折叠当前括号", "Fold Current Bracket")) {
                    handle(.native(.foldCurrentJSON))
                }
                .disabled(workspace.activeDocument?.language != .json
                    && workspace.activeDocument?.language != .jsonc)

                Button(preferences.tr("折叠全部 JSON", "Fold All JSON")) {
                    handle(.native(.foldAllJSON))
                }
                .disabled(workspace.activeDocument?.language != .json
                    && workspace.activeDocument?.language != .jsonc)

                Button(preferences.tr("展开全部 JSON", "Unfold All JSON")) {
                    handle(.native(.unfoldAllJSON))
                }
                .disabled(workspace.activeDocument?.language != .json
                    && workspace.activeDocument?.language != .jsonc)

                Menu(preferences.tr("行操作", "Line Operations")) {
                    ForEach(LineEditingAction.allCases) { action in
                        Button(preferences.title(for: action)) {
                            if let document = workspace.activeDocument {
                                workspace.apply(action, to: document)
                            }
                        }
                    }
                }

                Menu(preferences.tr("文本转换", "Convert Text")) {
                    ForEach(TextTransformation.allCases) { transformation in
                        Button(preferences.title(for: transformation)) {
                            if let document = workspace.activeDocument {
                                workspace.apply(transformation, to: document)
                            }
                        }
                    }
                }

                Toggle(preferences.tr("自动换行", "Word Wrap"), isOn: $preferences.wordWrap)
                Toggle(preferences.tr("显示行号", "Line Numbers"), isOn: $preferences.showLineNumbers)
                Toggle(preferences.tr("显示空白字符", "Whitespace"), isOn: $preferences.showWhitespace)

                Button(preferences.tr("文档信息", "Document Info")) {
                    workspace.showBottomPanel(.statistics)
                }

                Divider()

                Button("快捷键管理…") {
                    isShortcutManagerPresented = true
                }

                Button(preferences.tr("偏好设置…", "Preferences…")) {
                    isSettingsPresented = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel(preferences.tr("更多操作", "More actions"))
            .toolbarTip("更多编辑工具和偏好设置")
            }
            */
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(EditorChrome.background)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .overlayPreferenceValue(ToolbarTipAnchorKey.self) { anchors in
            ToolbarTipOverlay(anchors: anchors, event: toolbarTip)
        }
    }

    private var documentCommandBarTitle: some View {
        // The active file and group are already visible in the sidebar and
        // tab strip. Keep this command-bar slot empty; the signature lives in
        // the window title-bar above it.
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }

    private var helpersAndMoreMenu: some View {
        Menu {
            Section("面板") {
                Button("函数列表") { handle(.showFunctionList) }
                Button("书签面板") { handle(.showBookmarksPanel) }
                Button("文档信息") { handle(.showDocumentInfo) }
                Button("在文件中查找…") { handle(.findInFiles) }
            }
            Section("辅助工具") {
                Button("搜索文件…") { openFileSearchFromMenu() }
                Button("搜索代码片段…") { openSnippetsPalette(mode: .search) }
                Button("新建代码片段…") { openSnippetsPalette(mode: .create) }
                Button("剪贴板历史…") { openClipboardHistory() }
                Button("命令面板…") { isCommandPalettePresented = true }
            }
            Divider()
            Button("打开辅助功能设置…") { openAccessibilitySettings() }
            Button("配置工具栏…") { isToolbarCustomizationPresented = true }
            Button("恢复默认工具栏") { preferences.resetToolbarItems() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(width: 28, height: 28)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("辅助工具与更多")
        .toolbarTip("函数列表、搜索文件、代码片段、剪贴板等")
    }

    private var commandBarDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 2)
    }

    private func commandBarGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(4)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func toolbarButton(for item: EditorToolbarItem) -> some View {
        switch item {
        case .columnMode:
            Button { toggleColumnMode() } label: { Image(systemName: preferences.columnMode ? "rectangle.split.3x1.fill" : item.icon).frame(width: 28, height: 28) }
                .buttonStyle(.plain).foregroundStyle(preferences.columnMode ? .green : .primary).toolbarTip("列模式")
        case .find:
            Button { workspace.presentFindBar() } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.buttonStyle(.plain).toolbarTip("查找与替换")
        case .findInFiles:
            Button { workspace.showBottomPanel(.search) } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.buttonStyle(.plain).toolbarTip("在文件中查找")
        case .splitEditor:
            Button { workspace.toggleSplitEditor() } label: { Image(systemName: workspace.isSplitEditorPresented ? "rectangle.split.2x1.fill" : item.icon).frame(width: 28, height: 28) }.buttonStyle(.plain).toolbarTip("左右分栏")
        case .markdownPreview:
            Button { workspace.isMarkdownPreviewPresented.toggle() } label: { Image(systemName: workspace.isMarkdownPreviewPresented ? "rectangle.righthalf.inset.filled" : item.icon).frame(width: 28, height: 28) }.buttonStyle(.plain).toolbarTip("Markdown 预览")
        case .commandPalette:
            Button { isCommandPalettePresented = true } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.buttonStyle(.plain).toolbarTip("命令面板")
        case .functionList:
            Button { handle(.showFunctionList) } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }
                .buttonStyle(.plain)
                .toolbarTip("函数列表（视图菜单 / 底部面板）")
        case .fileSearch:
            Button { openFileSearchFromMenu() } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }
                .buttonStyle(.plain)
                .toolbarTip("搜索文件（⇧⌘O）")
        case .snippets:
            Button { openSnippetsPalette(mode: .search) } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }
                .buttonStyle(.plain)
                .toolbarTip("代码片段（⌥⌘S，可粘贴到任意应用光标处）")
        case .clipboardHistory:
            Button { openClipboardHistory() } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }
                .buttonStyle(.plain)
                .toolbarTip("剪贴板历史（⇧⌘V，粘贴到原光标处）")
        case .font:
            Menu { ForEach(EditorPreferences.editorFonts, id: \.self) { name in Button(fontDisplayName(name)) { preferences.fontName = name } } } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.menuStyle(.borderlessButton).toolbarTip("字体")
        case .fontSize:
            Menu { ForEach([10,12,14,15,16,18,20,24,28,32,36,40], id: \.self) { size in Button("\(size) 磅") { preferences.fontSize = Double(size) } } } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.menuStyle(.borderlessButton).toolbarTip("字体大小")
        case .lineSpacing:
            Menu { ForEach([0.0, 2.0, 4.0, 6.0, 8.0], id: \.self) { value in Button("\(Int(value)) 磅") { preferences.lineSpacing = value } } } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.menuStyle(.borderlessButton).toolbarTip("行间距")
        case .alignment:
            Menu { ForEach(EditorTextAlignment.allCases) { value in Button { preferences.textAlignment = value } label: { Label(value.title, systemImage: value.icon) } } } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.menuStyle(.borderlessButton).toolbarTip("文本对齐")
        case .wordWrap:
            Toggle(isOn: $preferences.wordWrap) { Image(systemName: item.icon).frame(width: 28, height: 28) }.toggleStyle(.button).toolbarTip("自动换行")
        case .lineNumbers:
            Toggle(isOn: $preferences.showLineNumbers) { Image(systemName: item.icon).frame(width: 28, height: 28) }.toggleStyle(.button).toolbarTip("显示行号")
        case .whitespace:
            Toggle(isOn: $preferences.showWhitespace) { Image(systemName: item.icon).frame(width: 28, height: 28) }.toggleStyle(.button).toolbarTip("显示空白字符")
        case .bookmark:
            Button { if let document = workspace.activeDocument { workspace.toggleBookmark(in: document) } } label: { Image(systemName: item.icon).frame(width: 28, height: 28) }.buttonStyle(.plain).toolbarTip("切换书签")
        case .more:
            EmptyView()
        }
    }

    @ViewBuilder
    private var settingsFloatingOverlay: some View {
        if isSettingsPresented {
            FloatingPanelHost(
                isPresented: $isSettingsPresented,
                title: preferences.tr("偏好设置", "Preferences"),
                initialSize: CGSize(width: 980, height: 720)
            ) {
                SettingsView(preferences: preferences) {
                    isSettingsPresented = false
                }
            }
            .zIndex(50)
        }
    }

    @ViewBuilder
    private var fileSearchFloatingOverlay: some View {
        if isFileSearchPresented {
            FloatingPanelHost(
                isPresented: $isFileSearchPresented,
                title: preferences.tr("搜索文件", "Search Files")
            ) {
                FileSearchView(
                    workspace: workspace,
                    preferences: preferences,
                    dismiss: { isFileSearchPresented = false },
                    fillsAvailableSpace: true
                )
            }
            .zIndex(40)
        }
    }

    @ViewBuilder
    private var snippetsFloatingOverlay: some View {
        if isSnippetsPresented {
            FloatingPanelHost(
                isPresented: $isSnippetsPresented,
                title: preferences.tr("代码片段", "Snippets")
            ) {
                SnippetsView(
                    workspace: workspace,
                    preferences: preferences,
                    initialMode: snippetsEntryMode,
                    fillsAvailableSpace: true,
                    dismiss: { isSnippetsPresented = false }
                )
            }
            .zIndex(45)
        }
    }

    @ViewBuilder
    private var clipboardFloatingOverlay: some View {
        if isClipboardHistoryPresented {
            FloatingPanelHost(
                isPresented: $isClipboardHistoryPresented,
                title: preferences.tr("剪贴板历史", "Clipboard History")
            ) {
                ClipboardHistoryView(
                    workspace: workspace,
                    preferences: preferences,
                    fillsAvailableSpace: true,
                    dismiss: { isClipboardHistoryPresented = false }
                )
            }
            .zIndex(46)
        }
    }

    private func installSnippetGlobalHotKey() {
        #if targetEnvironment(macCatalyst)
        SnippetGlobalHotKey.shared.onPressed = {
            NotificationCenter.default.post(name: .openSnippetsGlobalHotKey, object: nil)
        }
        SnippetGlobalHotKey.shared.start()
        #endif
    }

    private func openSnippetsFromGlobalHotKey() {
        // Capture the other app *before* we become frontmost (Raycast order).
        SystemSnippetBridge.captureFrontmostApplication()
        SystemSnippetBridge.promptAccessibilityIfNeeded()
        snippetsEntryMode = .search
        isSnippetsPresented = true
        #if targetEnvironment(macCatalyst)
        activateSelfApplication()
        #endif
    }

    private func openSnippetsPalette(mode: SnippetsEntryMode) {
        SystemSnippetBridge.captureFrontmostApplication()
        snippetsEntryMode = mode
        isSnippetsPresented = true
    }

    private func openClipboardHistory() {
        SystemSnippetBridge.captureFrontmostApplication()
        SystemSnippetBridge.promptAccessibilityIfNeeded()
        isClipboardHistoryPresented = true
    }

    private func openFileSearchFromMenu() {
        isFileSearchPresented = true
    }

    private func externalFileChangeAlert(for change: ExternalFileChange) -> Alert {
        // Capture the change by value — on Catalyst, SwiftUI often clears the
        // `alert(item:)` binding before the button action runs, which made
        // “重新载入” a no-op when it only read `workspace.externalFileChange`.
        let captured = change
        let isDirty = workspace.isDocumentDirtyForExternalChange(change)
        let message = isDirty
            ? preferences.tr(
                "文件已在其他程序中修改。重新载入会放弃当前未保存内容。",
                "This file changed outside NotepadPlus. Reloading will discard your unsaved changes."
            )
            : preferences.tr(
                "文件已在其他程序中修改，是否重新载入？",
                "This file changed outside NotepadPlus. Reload it now?"
            )
        let reload = Alert.Button.default(Text(preferences.tr("重新载入", "Reload"))) {
            workspace.handleExternalFileChange(captured, reload: true)
        }
        let destructiveReload = Alert.Button.destructive(Text(preferences.tr("重新载入", "Reload"))) {
            workspace.handleExternalFileChange(captured, reload: true)
        }
        return Alert(
            title: Text(preferences.tr("文件发生变化", "File Changed")),
            message: Text("\(change.fileName)\n\(message)"),
            primaryButton: isDirty ? destructiveReload : reload,
            secondaryButton: .cancel(Text(preferences.tr("保留当前内容", "Keep Current"))) {
                workspace.handleExternalFileChange(captured, reload: false)
            }
        )
    }

    private func openAccessibilitySettings() {
        SystemSnippetBridge.promptAccessibilityIfNeeded()
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"),
            URL(string: "x-apple.systempreferences:com.apple.preference.security")
        ].compactMap { $0 }
        for url in urls {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }

    #if targetEnvironment(macCatalyst)
    private func activateSelfApplication() {
        guard let bid = Bundle.main.bundleIdentifier,
              let cls = NSClassFromString("NSRunningApplication") as? NSObject.Type,
              let method = class_getClassMethod(cls, NSSelectorFromString("runningApplicationsWithBundleIdentifier:"))
        else { return }
        typealias Fn = @convention(c) (AnyClass, Selector, NSString) -> Unmanaged<NSArray>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        guard let apps = fn(cls, NSSelectorFromString("runningApplicationsWithBundleIdentifier:"), bid as NSString)?
            .takeUnretainedValue(),
              let app = apps.firstObject as? NSObject
        else { return }
        let sel = NSSelectorFromString("activateWithOptions:")
        guard let activateMethod = class_getInstanceMethod(object_getClass(app), sel) else { return }
        typealias ActivateFn = @convention(c) (AnyObject, Selector, UInt) -> Bool
        let activate = unsafeBitCast(method_getImplementation(activateMethod), to: ActivateFn.self)
        _ = activate(app, sel, 1 << 1)
    }
    #endif

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { workspace.errorMessage != nil },
            set: { newValue in
                if !newValue {
                    workspace.errorMessage = nil
                }
            }
        )
    }

    private func saveActiveDocument() {
        guard let document = workspace.activeDocument else { return }
        save(document, closeAfterSaving: false)
    }

    private func handle(_ command: DesktopCommand) {
        switch command {
        case .newDocument:
            workspace.newDocument()
        case .openDocument:
            isImporterPresented = true
        case .openWorkspace:
            isFolderImporterPresented = true
        case .newDocumentGroup:
            NotificationCenter.default.post(name: .requestNewDocumentGroup, object: nil)
        case .toggleSidebar:
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
        case .saveDocument:
            saveActiveDocument()
        case .saveAsDocument:
            if let document = workspace.activeDocument { beginExport(document) }
        case .saveAll:
            saveAllDocuments()
        case .closeActiveDocument:
            if let document = workspace.activeDocument { requestClose(document) }
        case .find:
            workspace.presentFindBar()
        case .replace:
            workspace.presentFindBar(replace: true)
        case .findInFiles:
            workspace.showBottomPanel(.search)
        case .goToLine:
            isGoToLinePresented = true
        case .toggleBookmark:
            if let document = workspace.activeDocument { workspace.toggleBookmark(in: document) }
        case .nextBookmark:
            workspace.activeDocument?.goToAdjacentBookmark(forward: true)
        case .previousBookmark:
            workspace.activeDocument?.goToAdjacentBookmark(forward: false)
        case .toggleSplit:
            workspace.toggleSplitEditor()
        case .nextTab:
            workspace.activateNextDocument(forward: true)
        case .previousTab:
            workspace.activateNextDocument(forward: false)
        case .duplicateActiveDocument:
            workspace.duplicateActiveDocument()
        case .sortDocumentsByName:
            workspace.sortDocumentsByName()
        case .closeUnchangedDocuments:
            workspace.closeUnchangedDocuments()
        case .showDocumentInfo:
            workspace.showBottomPanel(.statistics)
        case .showFunctionList:
            workspace.showBottomPanel(.functionList)
        case .showBookmarksPanel:
            workspace.showBottomPanel(.bookmarks)
        case .showJSONPath:
            workspace.showBottomPanel(.jsonPath)
        case .validateJSON:
            // Open the toolbox and ask it to validate immediately so the
            // command really performs "JSON 错误定位" instead of merely
            // navigating to a panel where the user has to click again.
            workspace.showBottomPanel(.jsonTools)
            if let document = workspace.activeDocument {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .jsonValidationRequested,
                        object: document.id
                    )
                }
            }
        case .showJSONTree:
            workspace.showBottomPanel(.jsonTree)
        case .showJSONTools:
            workspace.showBottomPanel(.jsonTools)
        case .transformText(let transformation):
            if let document = workspace.activeDocument { workspace.apply(transformation, to: document) }
        case .editLine(let action):
            if let document = workspace.activeDocument { workspace.apply(action, to: document) }
        case .native(let action):
            if !action.performStandardEditAction() {
                NotificationCenter.default.post(name: .editorNativeAction, object: action)
            }
        case .toggleMarkdownPreview:
            workspace.isMarkdownPreviewPresented.toggle()
        case .toggleColumnMode:
            toggleColumnMode()
        case .openPreferences:
            isSettingsPresented = true
        case .openShortcutManager:
            isShortcutManagerPresented = true
        case .customizeToolbar:
            isToolbarCustomizationPresented = true
        case .showCommandPalette:
            isCommandPalettePresented = true
        case .quickOpen:
            isQuickOpenPresented = true
        case .showFileSearch:
            isFileSearchPresented = true
        case .showSnippets:
            openSnippetsPalette(mode: .search)
        case .showCreateSnippet:
            openSnippetsPalette(mode: .create)
        case .showClipboardHistory:
            openClipboardHistory()
        case .showAbout:
            isAboutPresented = true
        case .showReleaseNotes:
            isReleaseNotesPresented = true
        case .zoom(let delta):
            if delta == 0 {
                preferences.fontSize = 15
            } else {
                preferences.fontSize = min(40, max(9, preferences.fontSize + delta))
            }
        }
    }

    private func performShortcutAction(_ action: ShortcutAction) {
        switch action {
        case .newDocument: handle(.newDocument)
        case .openDocument: handle(.openDocument)
        case .saveDocument: handle(.saveDocument)
        case .saveAs: handle(.saveAsDocument)
        case .saveAll: handle(.saveAll)
        case .closeDocument: handle(.closeActiveDocument)
        case .find: handle(.find)
        case .replace: handle(.replace)
        case .findInFiles: handle(.findInFiles)
        case .undo: handle(.native(.undo))
        case .redo: handle(.native(.redo))
        case .cut: handle(.native(.cut))
        case .copy: handle(.native(.copy))
        case .paste: handle(.native(.paste))
        case .selectAll: handle(.native(.selectAll))
        case .selectNextOccurrence: handle(.native(.selectNextOccurrence))
        case .duplicateLine: handle(.editLine(.duplicate))
        case .deleteLine: handle(.editLine(.delete))
        case .moveLineUp: handle(.editLine(.moveUp))
        case .moveLineDown: handle(.editLine(.moveDown))
        case .toggleComment: handle(.editLine(.toggleComment))
        case .indent: handle(.editLine(.indent))
        case .outdent: handle(.editLine(.outdent))
        case .goToLine: handle(.goToLine)
        case .markdownPreview: handle(.toggleMarkdownPreview)
        case .toggleColumnMode: handle(.toggleColumnMode)
        case .toggleSplitEditor: handle(.toggleSplit)
        case .showFunctionList: handle(.showFunctionList)
        case .nextTab: handle(.nextTab)
        case .previousTab: handle(.previousTab)
        case .duplicateTab: handle(.duplicateActiveDocument)
        case .toggleBookmark: handle(.toggleBookmark)
        case .nextBookmark: handle(.nextBookmark)
        case .previousBookmark: handle(.previousBookmark)
        case .zoomIn: handle(.zoom(1))
        case .zoomOut: handle(.zoom(-1))
        case .resetZoom: handle(.zoom(0))
        case .openShortcutManager: handle(.openShortcutManager)
        }
    }

    private func saveAllDocuments() {
        workspace.saveAllExistingDocuments()
        let unsaved = workspace.documents.filter { $0.isDirty && $0.fileURL == nil }
        if unsaved.count == 1, let only = unsaved.first {
            beginExport(only)
        } else if unsaved.count > 1 {
            workspace.errorMessage = preferences.tr(
                "已保存所有具名文件；仍有 \(unsaved.count) 个未命名文档需要选择保存位置，请分别保存这些标签页。",
                "Saved all named files. \(unsaved.count) untitled documents still need a destination; save those tabs individually."
            )
        }
    }

    private func toggleColumnMode() {
        preferences.columnMode.toggle()
        if !preferences.columnMode {
            NotificationCenter.default.post(name: .editorNativeAction, object: EditorNativeAction.clearColumnSelection)
        }
    }

    private var exportDefaultFilename: String {
        guard let exportingDocumentID else {
            return workspace.activeDocument?.title ?? preferences.tr("未命名.txt", "untitled.txt")
        }
        return workspace.documents.first(where: { $0.id == exportingDocumentID })?.title
            ?? preferences.tr("未命名.txt", "untitled.txt")
    }

    private func save(_ document: EditorDocument, closeAfterSaving: Bool) {
        if document.fileURL == nil {
            closeAfterExport = closeAfterSaving
            beginExport(document)
            return
        }

        do {
            try workspace.save(document)
            if closeAfterSaving {
                workspace.close(document)
                documentPendingClose = nil
            }
        } catch {
            workspace.errorMessage = preferences.tr("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
        }
    }

    private func beginExport(_ document: EditorDocument) {
        // The system exporter writes its payload before completeExport runs;
        // block unloaded placeholders before creating that payload as well.
        guard document.fileAccessError == nil else {
            workspace.requestFileAccess(for: document)
            return
        }
        exportingDocumentID = document.id
        exportPayload = ExportTextDocument(document: document)
        isExporterPresented = true
    }

    private func completeExport(_ result: Result<URL, Error>) {
        defer {
            exportPayload = nil
            exportingDocumentID = nil
            closeAfterExport = false
        }

        switch result {
        case .success(let url):
            guard let id = exportingDocumentID,
                  let document = workspace.documents.first(where: { $0.id == id })
            else { return }
            do {
                try workspace.save(document, to: url)
                if closeAfterExport {
                    workspace.close(document)
                    documentPendingClose = nil
                }
            } catch {
                workspace.errorMessage = preferences.tr("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
            }
        case .failure(let error):
            workspace.errorMessage = preferences.tr("导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
        }
    }

    private func requestClose(_ document: EditorDocument) {
        if document.isDirty {
            documentPendingClose = document
            showCloseConfirmation = true
        } else {
            workspace.close(document)
        }
    }

    private func fontDisplayName(_ fontName: String) -> String {
        fontName == "SFMono-Regular" ? "SF Mono" : fontName
    }
}

private struct ToolbarCustomizationView: View {
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var items: [EditorToolbarItem]

    init(preferences: EditorPreferences) {
        self.preferences = preferences
        _items = State(initialValue: preferences.toolbarItems)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("已显示工具（拖动调整顺序）") {
                    ForEach(items) { item in
                        Label(item.title, systemImage: item.icon)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }
                }
                Section("添加工具") {
                    ForEach(EditorToolbarItem.allCases.filter { !items.contains($0) }) { item in
                        Button { items.append(item) } label: { Label(item.title, systemImage: item.icon) }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("配置工具栏")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { preferences.toolbarItems = items; dismiss() } }
            }
        }
    }
}

/// Displays one user-maintained signature at a time in the window title bar.
/// TimelineView avoids retaining a timer and rotates automatically while the toolbar is visible.
private struct SignatureTopBar: View {
    @ObservedObject var preferences: EditorPreferences

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Text("NotepadPlus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 14)
                .padding(.trailing, 18)
                .fixedSize()
            SignatureTickerView(preferences: preferences)
                .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .center)
        }
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .center)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.18))
                .frame(height: 1)
        }
        .clipped()
        .accessibilityElement(children: .contain)
    }
}

private struct SignatureTickerView: View {
    @ObservedObject var preferences: EditorPreferences

    var body: some View {
        let quotes = preferences.activeSignatureTexts
        if preferences.signatureEnabled, !quotes.isEmpty {
            Group {
                switch preferences.signatureStyle {
                case .marquee:
                    SignatureMarqueeView(quotes: quotes, preferences: preferences)
                case .blinds:
                    SignatureBlindsView(quotes: quotes, preferences: preferences)
                case .typewriter:
                    SignatureTypewriterView(quotes: quotes, preferences: preferences)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)
        }
    }
}

/// Shared helpers for title-bar signature playback — every style must finish
/// showing the full quote before advancing to the next one.
private enum SignaturePlayback {
    /// Lines for blinds: prefer author newlines; otherwise chunk long prose.
    static func displayLines(for quote: String) -> [String] {
        let raw = quote
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if raw.isEmpty { return [] }
        if raw.count > 1 { return raw }
        return chunkProse(raw[0], softLimit: 32)
    }

    /// Flatten multiline quotes into one marquee / typewriter string.
    static func continuousText(for quote: String) -> String {
        quote
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    static func chunkProse(_ text: String, softLimit: Int) -> [String] {
        guard text.count > softLimit else { return [text] }
        let breakers: Set<Character> = ["。", "！", "？", "；", "!", "?", ";", "，", ",", "、"]
        var chunks: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            let shouldBreak = breakers.contains(ch) && current.count >= max(12, softLimit / 2)
            let forced = current.count >= softLimit + 8
            if shouldBreak || forced {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { chunks.append(piece) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks.isEmpty ? [text] : chunks
    }

    static func measureWidth(_ text: String, font: UIFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    static func uiFont(name: String, size: CGFloat) -> UIFont {
        UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }
}

#if targetEnvironment(macCatalyst)

enum TitlebarQuoteLayout {
    /// Leading X of the detail column in window coordinates; 0 = unknown/hidden sidebar.
    private(set) static var detailMinX: CGFloat = 0

    static func setDetailMinX(_ raw: CGFloat) {
        guard raw.isFinite, raw >= 0 else { return }
        if raw < 80 || raw > 900 {
            detailMinX = 0
            return
        }
        detailMinX = raw
    }
}

private struct DetailOriginKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DetailOriginReporter: View {
    var body: some View {
        GeometryReader { geo in
            let minX = geo.frame(in: .global).minX
            Color.clear
                .preference(key: DetailOriginKey.self, value: minX)
                .onAppear { TitlebarQuoteLayout.setDetailMinX(minX) }
                .onChange(of: minX) { _, value in TitlebarQuoteLayout.setDetailMinX(value) }
        }
        .allowsHitTesting(false)
    }
}

/// Hosts the quote inside the unified titlebar (fills the top chrome band).
private struct TitlebarQuoteBridge: UIViewRepresentable {
    @ObservedObject var preferences: EditorPreferences

    func makeCoordinator() -> TitlebarQuoteConfigurator { TitlebarQuoteConfigurator() }

    func makeUIView(context: Context) -> TitlebarWindowProbe {
        let probe = TitlebarWindowProbe()
        probe.isUserInteractionEnabled = false
        probe.onLayout = { [weak coordinator = context.coordinator] window in
            coordinator?.scheduleUpdate(window: window)
        }
        context.coordinator.preferences = preferences
        return probe
    }

    func updateUIView(_ probe: TitlebarWindowProbe, context: Context) {
        context.coordinator.preferences = preferences
        if let window = probe.window { context.coordinator.scheduleUpdate(window: window) }
    }
}

private final class TitlebarWindowProbe: UIView {
    var onLayout: ((UIWindow) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { onLayout?(window) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let window { onLayout?(window) }
    }
}

@MainActor
private final class TitlebarQuoteConfigurator: NSObject, NSToolbarDelegate {
    var preferences: EditorPreferences? {
        didSet {
            if let preferences, oldValue !== preferences {
                hosting?.rootView = TitlebarQuoteView(preferences: preferences)
            }
        }
    }

    private let quoteIdentifier = NSToolbarItem.Identifier("NotepadPlus.quote")
    private weak var scene: UIWindowScene?
    private var toolbar: NSToolbar?
    private var hosting: UIHostingController<TitlebarQuoteView>?
    private var container: TitlebarQuoteContainerView?
    private var toolbarItem: NSUIViewToolbarItem?
    private var itemWidth: CGFloat = 200
    private var coordinateScale: CGFloat = 1
    private weak var pendingWindow: UIWindow?
    private var updateScheduled = false

    func scheduleUpdate(window: UIWindow) {
        pendingWindow = window
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            if let window = self.pendingWindow { self.update(window: window) }
        }
    }

    private func update(window: UIWindow) {
        guard let scene = window.windowScene, let titlebar = scene.titlebar,
              preferences != nil else { return }
        window.backgroundColor = EditorChrome.uiBackground
        if let root = window.rootViewController {
            root.view.backgroundColor = EditorChrome.uiBackground
            configureWindowChrome(in: root)
        }

        if self.scene !== scene {
            let nativeWidth = scene.effectiveGeometry.systemFrame.width
            coordinateScale = nativeWidth > 0 ? window.bounds.width / nativeWidth : 1
        }

        // Traffic-light clearance for a single leading toolbar item.
        let trafficLights = 88 * coordinateScale
        let trailing = 12 * coordinateScale
        let uikitDetail = uiKitDetailMinX(in: window)
        let detailMinX = uikitDetail > 0 ? uikitDetail : TitlebarQuoteLayout.detailMinX
        // Internal pad only (no spacer item) — one-shot from detail edge, never accumulates.
        let pad = detailMinX >= trafficLights + 40
            ? max(0, detailMinX - trafficLights)
            : 0
        let nextWidth = max(120, window.bounds.width - trafficLights - trailing)

        if self.scene !== scene || toolbar == nil {
            self.scene = scene
            hosting = nil
            container = nil
            toolbarItem = nil
            let toolbar = NSToolbar(identifier: NSToolbar.Identifier("NotepadPlus.titlebar.quoteOnly.\(scene.session.persistentIdentifier)"))
            toolbar.delegate = self
            toolbar.allowsUserCustomization = false
            toolbar.autosavesConfiguration = false
            toolbar.displayMode = .iconOnly
            toolbar.centeredItemIdentifiers = []
            self.toolbar = toolbar
            titlebar.titleVisibility = .hidden
            titlebar.toolbarStyle = .unifiedCompact
            titlebar.separatorStyle = .none
            titlebar.toolbar = toolbar
        }

        itemWidth = nextWidth
        if let container {
            if abs(container.preferredWidth - itemWidth) > 0.5 {
                container.preferredWidth = itemWidth
                toolbarItem?.uiView = container
            }
            if abs(container.leadingPad - pad) > 0.75 {
                container.leadingPad = pad
            }
        }

        let report = [
            "detailMinX=\(Int(detailMinX))",
            "pad=\(Int(pad))",
            "traffic=\(Int(trafficLights))",
            "quoteStart=\(Int(trafficLights + pad))",
            "quoteWidth=\(Int(itemWidth))",
            "window=\(Int(window.bounds.width))",
            "scale=\(String(format: "%.3f", coordinateScale))"
        ].joined(separator: " ")
        try? report.write(toFile: "/tmp/notepadplus-titlebar-layout.txt", atomically: true, encoding: .utf8)
    }

    private func uiKitDetailMinX(in window: UIWindow) -> CGFloat {
        guard let root = window.rootViewController,
              let split = findSplitViewController(in: root),
              !split.isCollapsed,
              let detail = split.viewController(for: .secondary)?.viewIfLoaded
                ?? split.viewController(for: .supplementary)?.viewIfLoaded
        else { return 0 }
        let x = detail.convert(CGPoint.zero, to: window).x
        guard x.isFinite, x >= 80, x <= window.bounds.width * 0.55 else { return 0 }
        return x
    }

    private func findSplitViewController(in controller: UIViewController) -> UISplitViewController? {
        if let split = controller as? UISplitViewController { return split }
        for child in controller.children {
            if let found = findSplitViewController(in: child) { return found }
        }
        return controller.presentedViewController.flatMap(findSplitViewController(in:))
    }

    private func configureWindowChrome(in controller: UIViewController) {
        if let split = controller as? UISplitViewController {
            if split.primaryBackgroundStyle != .none {
                split.primaryBackgroundStyle = .none
            }
            split.view.backgroundColor = EditorChrome.uiBackground
            split.viewController(for: .primary)?.viewIfLoaded?.backgroundColor = EditorChrome.uiBackground
        }
        if let navigation = controller as? UINavigationController {
            let bar = navigation.navigationBar
            if bar.standardAppearance.backgroundColor != EditorChrome.uiBackground {
                let appearance = UINavigationBarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = EditorChrome.uiBackground
                appearance.shadowColor = .clear
                bar.standardAppearance = appearance
                bar.scrollEdgeAppearance = appearance
                bar.compactAppearance = appearance
                bar.compactScrollEdgeAppearance = appearance
            }
            if bar.isTranslucent { bar.isTranslucent = false }
        }
        for child in controller.children {
            configureWindowChrome(in: child)
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [quoteIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [quoteIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == quoteIdentifier, let preferences else { return nil }
        let hosting = UIHostingController(rootView: TitlebarQuoteView(preferences: preferences))
        hosting.view.backgroundColor = .clear
        let uikitDetail = pendingWindow.map(uiKitDetailMinX(in:)) ?? 0
        let detailMinX = uikitDetail > 0 ? uikitDetail : TitlebarQuoteLayout.detailMinX
        let trafficLights = 88 * coordinateScale
        let pad = detailMinX >= trafficLights + 40 ? max(0, detailMinX - trafficLights) : 0
        let container = TitlebarQuoteContainerView(contentView: hosting.view, width: itemWidth, leadingPad: pad)
        self.hosting = hosting
        self.container = container
        let item = NSUIViewToolbarItem(itemIdentifier: itemIdentifier, uiView: container)
        item.isNavigational = true
        item.isBordered = false
        item.visibilityPriority = .high
        toolbarItem = item
        return item
    }
}

private final class TitlebarQuoteContainerView: UIView {
    var preferredWidth: CGFloat {
        didSet {
            guard abs(oldValue - preferredWidth) > 0.5 else { return }
            frame.size.width = preferredWidth
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    var leadingPad: CGFloat {
        didSet {
            guard abs(oldValue - leadingPad) > 0.5 else { return }
            leadingConstraint?.constant = max(0, leadingPad)
            setNeedsLayout()
        }
    }

    private var leadingConstraint: NSLayoutConstraint?

    init(contentView: UIView, width: CGFloat, leadingPad: CGFloat) {
        preferredWidth = width
        self.leadingPad = leadingPad
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: 28))
        backgroundColor = .clear
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        let leading = contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: max(0, leadingPad))
        leadingConstraint = leading
        NSLayoutConstraint.activate([
            leading,
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28)
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: preferredWidth, height: 28) }
}

private struct TitlebarQuoteView: View {
    @ObservedObject var preferences: EditorPreferences

    var body: some View {
        SignatureTickerView(preferences: preferences)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
            .clipped()
    }
}

#endif

/// Reads each quote head→tail in the title bar, then advances.
/// Long text starts with the beginning visible and scrolls until the ending
/// is fully shown; short text stays centered for the dwell time.
private struct SignatureMarqueeView: View {
    let quotes: [String]
    @ObservedObject var preferences: EditorPreferences

    private struct Segment {
        let text: String
        let textWidth: CGFloat
        let startHold: TimeInterval
        let scrollDuration: TimeInterval
        let endHold: TimeInterval

        var duration: TimeInterval { startHold + scrollDuration + endHold }
    }

    var body: some View {
        GeometryReader { proxy in
            let font = SignaturePlayback.uiFont(
                name: preferences.signatureFontName,
                size: preferences.signatureFontSize
            )
            let viewport = max(1, proxy.size.width)
            let segments = makeSegments(viewportWidth: viewport, font: font)
            let total = max(0.1, segments.reduce(0) { $0 + $1.duration })
            TimelineView(.periodic(from: .distantPast, by: 1.0 / 30.0)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let (segment, local) = locate(segments: segments, total: total, elapsed: elapsed)
                let offset = offsetX(for: segment, local: local, viewportWidth: viewport)
                Text(segment.text)
                    .font(Font(font))
                    .foregroundStyle(preferences.signatureColor)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(x: offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityLabel("个性化签名：\(segment.text)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    /// Head at the leading edge first (`offset = 0`); then move left until the
    /// tail reaches the trailing edge. Never starts from the tail.
    private func offsetX(for segment: Segment, local: TimeInterval, viewportWidth: CGFloat) -> CGFloat {
        let fits = segment.textWidth <= viewportWidth
        if fits {
            return (viewportWidth - segment.textWidth) / 2
        }
        let start: CGFloat = 0
        let end = viewportWidth - segment.textWidth // negative — reveals toward the ending
        if local <= segment.startHold {
            return start
        }
        if local >= segment.startHold + segment.scrollDuration {
            return end
        }
        let progress = (local - segment.startHold) / max(0.001, segment.scrollDuration)
        return start + CGFloat(progress) * (end - start)
    }

    private func makeSegments(viewportWidth: CGFloat, font: UIFont) -> [Segment] {
        let speed = max(22.0, preferences.signatureSpeed * 2.6) // points / second
        return quotes.map { quote in
            let body = SignaturePlayback.continuousText(for: quote)
            let text = "“\(body)”"
            let width = max(1, SignaturePlayback.measureWidth(text, font: font))
            let overflow = max(0, width - viewportWidth)
            let scroll = overflow <= 0 ? 0 : max(1.6, Double(overflow) / speed)
            let hold: TimeInterval = overflow <= 0 ? max(2.4, 48.0 / max(12, preferences.signatureSpeed)) : 0.7
            return Segment(
                text: text,
                textWidth: width,
                startHold: hold,
                scrollDuration: scroll,
                endHold: hold
            )
        }
    }

    private func locate(
        segments: [Segment],
        total: TimeInterval,
        elapsed: TimeInterval
    ) -> (Segment, TimeInterval) {
        guard !segments.isEmpty else {
            return (Segment(text: "", textWidth: 1, startHold: 1, scrollDuration: 0, endHold: 0), 0)
        }
        var cursor = elapsed.truncatingRemainder(dividingBy: total)
        if cursor < 0 { cursor += total }
        for segment in segments {
            if cursor < segment.duration {
                return (segment, cursor)
            }
            cursor -= segment.duration
        }
        return (segments.last!, segments.last!.duration)
    }
}

/// Blinds: show one line (or prose chunk) at a time with a vertical flip.
/// All lines of a quote finish before the next quote starts.
private struct SignatureBlindsView: View {
    let quotes: [String]
    @ObservedObject var preferences: EditorPreferences

    private struct Frame {
        let line: String
        let duration: TimeInterval
        let quoteIndex: Int
        let lineIndex: Int
    }

    var body: some View {
        let frames = makeFrames()
        let total = max(0.1, frames.reduce(0) { $0 + $1.duration })
        TimelineView(.periodic(from: .distantPast, by: 0.12)) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let frame = locate(frames: frames, total: total, elapsed: elapsed)
            Text("“\(frame.line)”")
                .font(.custom(preferences.signatureFontName, size: preferences.signatureFontSize))
                .foregroundStyle(preferences.signatureColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .id("\(frame.quoteIndex)-\(frame.lineIndex)")
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .animation(.easeInOut(duration: 0.45), value: "\(frame.quoteIndex)-\(frame.lineIndex)")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .accessibilityLabel("个性化签名：\(frame.line)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func makeFrames() -> [Frame] {
        let base = max(1.6, 52.0 / max(12, preferences.signatureSpeed))
        var frames: [Frame] = []
        for (quoteIndex, quote) in quotes.enumerated() {
            let lines = SignaturePlayback.displayLines(for: quote)
            for (lineIndex, line) in lines.enumerated() {
                let bonus = min(2.4, Double(line.count) / 28.0)
                frames.append(Frame(
                    line: line,
                    duration: base + bonus,
                    quoteIndex: quoteIndex,
                    lineIndex: lineIndex
                ))
            }
        }
        return frames
    }

    private func locate(frames: [Frame], total: TimeInterval, elapsed: TimeInterval) -> Frame {
        guard !frames.isEmpty else {
            return Frame(line: "", duration: 1, quoteIndex: 0, lineIndex: 0)
        }
        var cursor = elapsed.truncatingRemainder(dividingBy: total)
        if cursor < 0 { cursor += total }
        for frame in frames {
            if cursor < frame.duration { return frame }
            cursor -= frame.duration
        }
        return frames.last!
    }
}

/// Typewriter: reveal character by character at fixed size. When one visual
/// line is full, clear it and continue the remaining text from the left again
/// (never shrink, never scroll the line sideways).
private struct SignatureTypewriterView: View {
    let quotes: [String]
    @ObservedObject var preferences: EditorPreferences

    private struct Segment {
        let full: String
        let duration: TimeInterval
        let pause: TimeInterval
    }

    var body: some View {
        GeometryReader { proxy in
            let font = SignaturePlayback.uiFont(
                name: preferences.signatureFontName,
                size: preferences.signatureFontSize
            )
            let segments = makeSegments()
            let total = max(0.1, segments.reduce(0) { $0 + $1.duration + $1.pause })
            TimelineView(.periodic(from: .distantPast, by: 1.0 / 24.0)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let (segment, local) = locate(segments: segments, total: total, elapsed: elapsed)
                let typingWindow = max(0.05, segment.duration)
                let progress = min(1, max(0, local / typingWindow))
                let count = max(0, Int(ceil(progress * Double(segment.full.count))))
                let typed = String(segment.full.prefix(count))
                let display = currentTypewriterLine(
                    typed: typed,
                    maxWidth: max(1, proxy.size.width),
                    font: font
                )
                Text(display.isEmpty ? " " : display)
                    .font(Font(font))
                    .foregroundStyle(preferences.signatureColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .accessibilityLabel("个性化签名：\(segment.full)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
    }

    /// Pack typed characters into fixed-width lines; show only the active line
    /// so a full line restarts from the leading edge.
    private func currentTypewriterLine(typed: String, maxWidth: CGFloat, font: UIFont) -> String {
        guard !typed.isEmpty else { return "" }
        var current = ""
        for ch in typed {
            let trial = current + String(ch)
            if SignaturePlayback.measureWidth(trial, font: font) <= maxWidth {
                current = trial
            } else {
                current = String(ch)
            }
        }
        return current
    }

    private func makeSegments() -> [Segment] {
        let cps = max(6.0, preferences.signatureSpeed * 0.55) // characters / second
        return quotes.map { quote in
            let full = "“\(SignaturePlayback.continuousText(for: quote))”"
            let duration = max(1.8, Double(max(1, full.count)) / cps)
            return Segment(full: full, duration: duration, pause: 1.1)
        }
    }

    private func locate(
        segments: [Segment],
        total: TimeInterval,
        elapsed: TimeInterval
    ) -> (Segment, TimeInterval) {
        guard !segments.isEmpty else {
            return (Segment(full: "", duration: 1, pause: 0), 0)
        }
        var cursor = elapsed.truncatingRemainder(dividingBy: total)
        if cursor < 0 { cursor += total }
        for segment in segments {
            let span = segment.duration + segment.pause
            if cursor < span {
                // During pause keep showing the full text.
                return (segment, min(cursor, segment.duration))
            }
            cursor -= span
        }
        return (segments.last!, segments.last!.duration)
    }
}

struct ExportTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .text, .sourceCode] }

    private let data: Data

    init(document: EditorDocument) {
        data = document.textForSaving.data(using: document.encoding.stringEncoding)
            ?? Data(document.textForSaving.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension Notification.Name {
    static let desktopCommand = Notification.Name("NotepadPlus.desktopCommand")
    static let toolbarTipChanged = Notification.Name("NotepadPlus.toolbarTipChanged")
    static let jsonValidationRequested = Notification.Name("NotepadPlus.jsonValidationRequested")
    static let openSnippetsGlobalHotKey = Notification.Name("NotepadPlus.openSnippetsGlobalHotKey")
    static let openAccessibilitySettings = Notification.Name("NotepadPlus.openAccessibilitySettings")
}

enum DesktopCommand {
    case newDocument
    case openDocument
    case openWorkspace
    case newDocumentGroup
    case toggleSidebar
    case saveDocument
    case saveAsDocument
    case saveAll
    case closeActiveDocument
    case find
    case replace
    case findInFiles
    case goToLine
    case toggleBookmark
    case nextBookmark
    case previousBookmark
    case toggleSplit
    case nextTab
    case previousTab
    case duplicateActiveDocument
    case sortDocumentsByName
    case closeUnchangedDocuments
    case showDocumentInfo
    case showFunctionList
    case showBookmarksPanel
    case showJSONPath
    case validateJSON
    case showJSONTree
    case showJSONTools
    case transformText(TextTransformation)
    case editLine(LineEditingAction)
    case native(EditorNativeAction)
    case toggleMarkdownPreview
    case toggleColumnMode
    case openPreferences
    case openShortcutManager
    case customizeToolbar
    case showAbout
    case showReleaseNotes
    case zoom(Double)
    case showCommandPalette
    case quickOpen
    case showFileSearch
    case showSnippets
    case showCreateSnippet
    case showClipboardHistory
}

/// A searchable command launcher inspired by Notepad++'s command palette.
/// It intentionally uses the same DesktopCommand routing as the menus and
/// shortcut manager, so commands never drift apart in behaviour.
private struct CommandPaletteView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences
    let perform: (DesktopCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let command: DesktopCommand
    }

    private var items: [Item] {
        [
            Item(id: "new", title: "新建文档", subtitle: "文件", icon: "doc.badge.plus", command: .newDocument),
            Item(id: "open", title: "打开文件…", subtitle: "文件", icon: "folder", command: .openDocument),
            Item(id: "workspace", title: "打开文件夹工作区…", subtitle: "文件", icon: "folder.badge.gearshape", command: .openWorkspace),
            Item(id: "save", title: "保存", subtitle: "文件", icon: "square.and.arrow.down", command: .saveDocument),
            Item(id: "saveall", title: "全部保存", subtitle: "文件", icon: "square.and.arrow.down.on.square", command: .saveAll),
            Item(id: "close", title: "关闭当前文档", subtitle: "文件", icon: "xmark", command: .closeActiveDocument),
            Item(id: "find", title: "查找与替换", subtitle: "搜索", icon: "magnifyingglass", command: .find),
            Item(id: "findfiles", title: "在文件中查找", subtitle: "搜索", icon: "doc.text.magnifyingglass", command: .findInFiles),
            Item(id: "functions", title: "函数列表", subtitle: "视图 · 底部面板", icon: "list.bullet.rectangle", command: .showFunctionList),
            Item(id: "bookmarks-panel", title: "书签面板", subtitle: "视图 · 底部面板", icon: "bookmark", command: .showBookmarksPanel),
            Item(id: "doc-info", title: "文档信息", subtitle: "视图 · 底部面板", icon: "info.circle", command: .showDocumentInfo),
            Item(id: "select-next", title: "选择下一个匹配项", subtitle: "编辑", icon: "plus.magnifyingglass", command: .native(.selectNextOccurrence)),
            Item(id: "file-search", title: "搜索文件（全盘）…", subtitle: "搜索 / 辅助工具", icon: "doc.text.magnifyingglass", command: .showFileSearch),
            Item(id: "snippets", title: "搜索代码片段…", subtitle: "辅助工具", icon: "text.badge.plus", command: .showSnippets),
            Item(id: "snippets-create", title: "新建代码片段…", subtitle: "辅助工具", icon: "doc.badge.plus", command: .showCreateSnippet),
            Item(id: "clipboard", title: "剪贴板历史…", subtitle: "辅助工具", icon: "clipboard", command: .showClipboardHistory),
            Item(id: "line", title: "跳转到行…", subtitle: "搜索", icon: "text.line.first.and.arrowtriangle.forward", command: .goToLine),
            Item(id: "next", title: "下一个标签页", subtitle: "视图", icon: "arrow.right", command: .nextTab),
            Item(id: "previous", title: "上一个标签页", subtitle: "视图", icon: "arrow.left", command: .previousTab),
            Item(id: "markdown", title: "Markdown 预览", subtitle: "视图", icon: "text.document", command: .toggleMarkdownPreview),
            Item(id: "column", title: "列模式", subtitle: "视图", icon: "rectangle.split.3x1", command: .toggleColumnMode),
            Item(id: "format", title: "格式化 JSON", subtitle: "格式", icon: "curlybraces", command: .native(.formatJSON)),
            Item(id: "json-path", title: "JSONPath 查询", subtitle: "格式", icon: "point.3.connected.trianglepath.dotted", command: .showJSONPath),
            Item(id: "json-validate", title: "JSON 错误定位", subtitle: "格式", icon: "exclamationmark.triangle", command: .validateJSON),
            Item(id: "json-tree", title: "JSON 树视图", subtitle: "格式", icon: "list.bullet.indent", command: .showJSONTree),
            Item(id: "json-tools", title: "JSON 工具箱", subtitle: "格式", icon: "wrench.and.screwdriver", command: .showJSONTools),
            Item(id: "fold", title: "折叠当前括号", subtitle: "格式", icon: "chevron.down.square", command: .native(.foldCurrentJSON)),
            Item(id: "foldall", title: "折叠全部 JSON", subtitle: "格式", icon: "rectangle.compress.vertical", command: .native(.foldAllJSON)),
            Item(id: "unfoldall", title: "展开全部 JSON", subtitle: "格式", icon: "rectangle.expand.vertical", command: .native(.unfoldAllJSON)),
            Item(id: "duplicate", title: "复制行", subtitle: "编辑 · 行操作", icon: "plus.square.on.square", command: .editLine(.duplicate)),
            Item(id: "delete-line", title: "删除行", subtitle: "编辑 · 行操作", icon: "trash", command: .editLine(.delete)),
            Item(id: "move-up", title: "上移行", subtitle: "编辑 · 行操作", icon: "arrow.up", command: .editLine(.moveUp)),
            Item(id: "move-down", title: "下移行", subtitle: "编辑 · 行操作", icon: "arrow.down", command: .editLine(.moveDown)),
            Item(id: "join-lines", title: "合并行", subtitle: "编辑 · 行操作", icon: "arrow.right.and.line.vertical.and.arrow.left", command: .editLine(.joinWithNext)),
            Item(id: "remove-empty-lines", title: "删除空行", subtitle: "编辑 · 行操作", icon: "line.3.horizontal.decrease", command: .editLine(.removeEmptyLines)),
            Item(id: "sidebar", title: "显示或隐藏文档导航栏", subtitle: "视图", icon: "sidebar.left", command: .toggleSidebar),
            Item(id: "split", title: "切换分栏编辑", subtitle: "视图", icon: "rectangle.split.2x1", command: .toggleSplit),
            Item(id: "toolbar", title: "配置工具栏…", subtitle: "设置", icon: "slider.horizontal.3", command: .customizeToolbar),
            Item(id: "settings", title: "偏好设置…", subtitle: "设置", icon: "gearshape", command: .openPreferences),
            Item(id: "shortcuts", title: "快捷键管理…", subtitle: "设置", icon: "keyboard", command: .openShortcutManager)
        ]
    }

    private var filteredItems: [Item] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return items }
        return items.filter { ($0.title + $0.subtitle).localizedCaseInsensitiveContains(value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command.square")
                    .foregroundStyle(.tint)
                TextField("搜索命令…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { if let first = filteredItems.first { perform(first.command) } }
                Text("⌘⇧P")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if filteredItems.isEmpty {
                ContentUnavailableView("没有匹配的命令", systemImage: "magnifyingglass", description: Text("试试搜索“JSON”“行”或“保存”"))
            } else {
                List(filteredItems) { item in
                    Button {
                        perform(item.command)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .frame(width: 22)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 500, idealWidth: 620, minHeight: 450, idealHeight: 580)
        .navigationTitle("命令面板")
    }
}

/// Fast file/tab launcher. It searches open tabs first, then recent files and
/// files discovered in the current workspace. Selecting a result immediately
/// activates or opens it, keeping the interaction fast even for large files.
private struct QuickOpenView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences
    let dismiss: () -> Void
    @State private var query = ""

    private struct Candidate: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let document: EditorDocument?
        let url: URL
    }

    private var candidates: [Candidate] {
        var result: [Candidate] = []
        var seen = Set<String>()
        for document in workspace.documents {
            guard let url = document.fileURL else { continue }
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            result.append(Candidate(id: "open-\(key)", title: document.title,
                                    detail: "已打开 · \(url.deletingLastPathComponent().path)", icon: "doc.text", document: document, url: url))
        }
        for url in workspace.recentFiles {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted, FileManager.default.fileExists(atPath: key) else { continue }
            result.append(Candidate(id: "recent-\(key)", title: url.lastPathComponent,
                                    detail: "最近使用 · \(url.deletingLastPathComponent().path)", icon: "clock", document: nil, url: url))
        }
        for url in workspace.workspaceFiles {
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted else { continue }
            result.append(Candidate(id: "workspace-\(key)", title: url.lastPathComponent,
                                    detail: "工作区 · \(url.deletingLastPathComponent().path)", icon: "folder", document: nil, url: url))
        }
        return result
    }

    private var filteredCandidates: [Candidate] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return Array(candidates.prefix(100)) }
        return candidates.filter { ($0.title + $0.detail).localizedCaseInsensitiveContains(value) }.prefix(100).map { $0 }
    }

    private func choose(_ candidate: Candidate) {
        if let document = candidate.document { workspace.activate(document) }
        else { workspace.open(url: candidate.url) }
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tint)
                TextField("按文件名或路径搜索…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { if let first = filteredCandidates.first { choose(first) } }
                Text("⌘P")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()
            if filteredCandidates.isEmpty {
                ContentUnavailableView("没有找到文件", systemImage: "doc.magnifyingglass", description: Text("尝试输入文件名、扩展名或路径"))
            } else {
                List(filteredCandidates) { candidate in
                    Button { choose(candidate) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: candidate.icon)
                                .frame(width: 22)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title)
                                    .lineLimit(1)
                                Text(candidate.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("快速打开")
    }
}

private struct AboutNotepadPlusView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isReleaseNotesPresented = false

    var body: some View {
        VStack(spacing: 14) {
            Image("BrandIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                .accessibilityLabel("NotepadPlus 应用图标")
            Text("NotepadPlus")
                .font(.title.bold())
            Text("中文桌面文本与代码编辑器")
                .foregroundStyle(.secondary)
            Link("开发者：wanglipingep@126.com", destination: URL(string: "mailto:wanglipingep@126.com")!)
                .font(.subheadline)
            Text(versionText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("查看版本更新记录") {
                isReleaseNotesPresented = true
            }
            .buttonStyle(.bordered)
            Button("完成") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .help("关闭关于窗口")
        }
        .padding(32)
        .frame(width: 400, height: 390)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .sheet(isPresented: $isReleaseNotesPresented) {
            ReleaseNotesView()
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.7"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "7"
        return "版本 \(version)（\(build)）"
    }
}

private struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss

    private let releases: [ReleaseNoteVersion] = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
              let content = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return ReleaseNotesParser.parse(content)
    }()

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? releases.first?.version
            ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.gradient)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text("版本更新记录")
                        .font(.title2.weight(.bold))
                    Text("了解 NotepadPlus 的新增功能、体验优化与重要修复")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !currentVersion.isEmpty {
                    Text("当前版本  \(currentVersion)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.11), in: Capsule())
                }

                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            .background(.regularMaterial)

            Divider()

            ScrollView {
                if releases.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("暂时无法读取版本更新内容")
                            .font(.headline)
                        Text("请确认 CHANGELOG.md 已包含在应用中。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 110)
                } else {
                    LazyVStack(spacing: 18) {
                        ForEach(releases) { release in
                            releaseCard(release)
                        }
                    }
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 600, idealHeight: 720)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }

    private func releaseCard(_ release: ReleaseNoteVersion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 13) {
                Text(release.version)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(release.version == currentVersion ? .white : .green)
                    .frame(minWidth: 58, minHeight: 42)
                    .padding(.horizontal, 5)
                    .background(
                        release.version == currentVersion
                            ? Color.green
                            : Color.green.opacity(0.11),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text("NotepadPlus \(release.version)")
                            .font(.headline)
                        if release.version == currentVersion {
                            Text("最新")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.1), in: Capsule())
                        }
                    }
                    Label(release.date, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(spacing: 12) {
                ForEach(Array(release.sections.enumerated()), id: \.offset) { _, section in
                    releaseSection(section)
                }
            }
        }
        .padding(20)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    release.version == currentVersion ? Color.green.opacity(0.32) : Color.secondary.opacity(0.13),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.045), radius: 12, y: 4)
        .textSelection(.enabled)
    }

    private func releaseSection(_ section: ReleaseNoteSection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: sectionIcon(section.title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
                .frame(width: 30, height: 30)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                Text(section.title)
                    .font(.subheadline.weight(.semibold))

                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle()
                            .fill(Color.green.opacity(0.72))
                            .frame(width: 5, height: 5)
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary.opacity(0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionIcon(_ title: String) -> String {
        if title.contains("编辑") { return "text.cursor" }
        if title.contains("文档") || title.contains("分组") { return "folder" }
        if title.contains("预览") || title.contains("Markdown") { return "doc.richtext" }
        if title.contains("修复") || title.contains("稳定") { return "wrench.and.screwdriver" }
        if title.contains("桌面") { return "macwindow" }
        return "sparkles"
    }
}

private struct GoToLineSheet: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var preferences: EditorPreferences
    @Binding var isPresented: Bool
    @State private var line = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(preferences.tr("跳转到行", "Go to Line"))
                .font(.title2.bold())
            Text(preferences.tr("行号范围：1 – \(document.lineCount)", "Line 1 – \(document.lineCount)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(preferences.tr("行号", "Line number"), text: $line)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit(go)
            HStack {
                Spacer()
                Button(preferences.tr("取消", "Cancel")) { isPresented = false }
                Button(preferences.tr("跳转", "Go"), action: go)
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(Int(line) == nil)
            }
        }
        .padding(22)
        .frame(width: 340)
        .onAppear {
            line = String(document.currentLine)
            isFocused = true
        }
    }

    private func go() {
        guard let destination = Int(line) else { return }
        document.goToLine(destination)
        isPresented = false
    }
}

// Dispatch standard editing commands once at the app menu boundary. Broadcasting
// them to every RootView would paste repeatedly when multiple windows are open.
extension EditorNativeAction {
    @MainActor
    @discardableResult
    func performStandardEditAction() -> Bool {
        let selector: Selector
        switch self {
        case .cut: selector = #selector(UIResponderStandardEditActions.cut(_:))
        case .copy: selector = #selector(UIResponderStandardEditActions.copy(_:))
        case .paste: selector = #selector(UIResponderStandardEditActions.paste(_:))
        case .selectAll: selector = #selector(UIResponderStandardEditActions.selectAll(_:))
        default: return false
        }
        UIApplication.shared.sendAction(selector, to: nil, from: nil, for: nil)
        return true
    }
}
