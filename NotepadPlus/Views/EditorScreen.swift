import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit
#if targetEnvironment(macCatalyst)
import Darwin
#endif

struct EditorScreen: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences

    @State private var markdownSplitRatio: CGFloat = 0.52
    @State private var isMarkdownPreviewFullScreen = false
    @State private var searchPanelHeight: CGFloat = 240

    var body: some View {
        VStack(spacing: 0) {
            DocumentTabStrip(workspace: workspace)

            if workspace.isFindBarPresented, document.fileAccessError == nil {
                FindReplaceBar(
                    document: document,
                    preferences: preferences,
                    state: workspace.findReplaceState,
                    isPresented: $workspace.isFindBarPresented,
                    onDocumentChange: { workspace.documentDidChange(document) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 0) {
                if document.fileAccessError != nil {
                    FileAccessRecoveryView(document: document, workspace: workspace)
                } else if isMarkdownPreviewFullScreen && workspace.isMarkdownPreviewPresented {
                    MarkdownPreviewPane(
                        document: document,
                        preferences: preferences,
                        isFullScreen: $isMarkdownPreviewFullScreen
                    )
                    .transition(.opacity)
                } else {
                    Group {
                        if workspace.isSplitEditorPresented, let secondary = workspace.secondaryDocument {
                            HStack(spacing: 0) {
                                EditorPane(
                                    document: document,
                                    workspace: workspace,
                                    preferences: preferences,
                                    showsHeader: true
                                )
                                Divider()
                                SecondaryEditorPane(
                                    document: secondary,
                                    workspace: workspace,
                                    preferences: preferences
                                )
                                .frame(minWidth: 360)
                            }
                        } else if workspace.isMarkdownPreviewPresented {
                            GeometryReader { proxy in
                                let dividerWidth: CGFloat = 9
                                let minimumEditor: CGFloat = 280
                                let minimumPreview: CGFloat = 280
                                let usableWidth = max(0, proxy.size.width - dividerWidth)
                                let editorWidth = min(
                                    max(usableWidth * markdownSplitRatio, minimumEditor),
                                    max(minimumEditor, usableWidth - minimumPreview)
                                )
                                HStack(spacing: 0) {
                                    EditorPane(
                                        document: document,
                                        workspace: workspace,
                                        preferences: preferences,
                                        showsHeader: false
                                    )
                                    .frame(width: editorWidth)
                                    MarkdownSplitDivider(
                                        ratio: $markdownSplitRatio,
                                        totalWidth: proxy.size.width
                                    )
                                        .frame(width: dividerWidth)
                                    MarkdownPreviewPane(
                                        document: document,
                                        preferences: preferences,
                                        isFullScreen: $isMarkdownPreviewFullScreen
                                    )
                                    .frame(width: max(minimumPreview, usableWidth - editorWidth))
                                    .transition(.opacity)
                                }
                            }
                        } else {
                            EditorPane(
                                document: document,
                                workspace: workspace,
                                preferences: preferences,
                                showsHeader: false
                            )
                        }
                    }
                    .background(preferences.themeBackgroundColor)
                }

                if workspace.isBottomPanelPresented {
                    Divider()
                    DesktopBottomPanel(
                        document: document,
                        workspace: workspace,
                        panelHeight: $searchPanelHeight
                    )
                    .frame(height: searchPanelHeight)
                }
            }

            EditorStatusBar(document: document, preferences: preferences)
                .disabled(document.fileAccessError != nil)
        }
        .animation(.easeInOut(duration: 0.18), value: workspace.isFindBarPresented)
        .animation(.easeInOut(duration: 0.18), value: isMarkdownPreviewFullScreen)
        .onChange(of: document.encoding) { _, _ in workspace.documentDidChange(document) }
        .onChange(of: document.lineEnding) { _, _ in workspace.documentDidChange(document) }
        .onChange(of: document.language) { _, _ in workspace.documentDidChange(document) }
        .onChange(of: workspace.isMarkdownPreviewPresented) { _, isPresented in
            if !isPresented { isMarkdownPreviewFullScreen = false }
        }
        .background(preferences.themeBackgroundColor)
    }
}

private struct FileAccessRecoveryView: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        ContentUnavailableView {
            Label(workspace.preferences.tr("文件暂时无法访问", "File Unavailable"), systemImage: "doc.badge.ellipsis")
        } description: {
            Text(workspace.preferences.tr(
                "文件记录和分组已保留。请确认磁盘已连接、文件仍在原位置；如果授权失效，请重新选择原文件，或授权其所在文件夹。",
                "The file and group membership have been kept. Check that the drive is connected and the file is at its original location, then select the file or authorize its containing folder."
            ))
            Text(document.fileURL?.path ?? document.title).font(.caption).textSelection(.enabled)
            Text(document.fileAccessError ?? "").font(.caption).foregroundStyle(.secondary)
        } actions: {
            Button(workspace.preferences.tr("重新选择文件…", "Select File Again…")) {
                workspace.requestFileAccess(for: document)
            }
            Button(workspace.preferences.tr("授权所在文件夹…", "Authorize Containing Folder…")) {
                workspace.requestFileAccess(for: document, folder: true)
            }
            Button(workspace.preferences.tr("重试载入", "Retry")) { workspace.reload(document) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EditorPane: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences
    let showsHeader: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Label(document.title, systemImage: "rectangle.leadinghalf.inset.filled")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text(workspace.preferences.tr("主编辑器", "PRIMARY"))
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }

            if document.fileAccessError != nil {
                FileAccessRecoveryView(document: document, workspace: workspace)
            } else {
            CodeEditorView(
                text: $document.content,
                contentRevision: document.contentRevision,
                selection: $document.selection,
                documentID: document.id,
                scrollOffset: workspace.scrollOffset(for: document),
                onScrollOffsetChange: { workspace.updateScrollOffset($0, for: document) },
                language: document.language,
                preferences: preferences,
                onTextChange: { workspace.documentDidChange(document) },
                onJSONFormattingError: { message in
                    workspace.errorMessage = preferences.tr(
                        "JSON 格式化失败：\(message)",
                        "JSON formatting failed: \(message)"
                    )
                },
                markdownScrollPosition: document.markdownScrollPosition,
                onMarkdownScroll: (document.language == .markdown || workspace.isMarkdownPreviewPresented) ? { position in
                    document.markdownScrollPosition = position
                    NotificationCenter.default.post(name: .markdownEditorDidScroll,
                        object: MarkdownScrollRequest(documentID: document.id, position: position))
                } : nil,
                isMarkdownPreviewPresented: workspace.isMarkdownPreviewPresented
            )
            .id(document.id)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
    }
}

private struct SecondaryEditorPane: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker(workspace.preferences.tr("副编辑器文档", "Secondary document"), selection: $workspace.secondaryDocumentID) {
                    ForEach(workspace.documents.filter { $0.id != workspace.activeDocumentID }) { candidate in
                        Text(candidate.title).tag(Optional(candidate.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                Spacer()
                Button {
                    workspace.isSplitEditorPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(workspace.preferences.tr("关闭分栏编辑", "Close split editor"))
                .help(workspace.preferences.tr("关闭分栏编辑", "Close split editor"))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            if document.fileAccessError != nil {
                FileAccessRecoveryView(document: document, workspace: workspace)
            } else {
            CodeEditorView(
                text: $document.content,
                contentRevision: document.contentRevision,
                selection: $document.selection,
                documentID: document.id,
                scrollOffset: workspace.scrollOffset(for: document),
                onScrollOffsetChange: { workspace.updateScrollOffset($0, for: document) },
                language: document.language,
                preferences: preferences,
                onTextChange: { workspace.documentDidChange(document) },
                onJSONFormattingError: { message in
                    workspace.errorMessage = preferences.tr(
                        "JSON 格式化失败：\(message)",
                        "JSON formatting failed: \(message)"
                    )
                }
            )
            .id(document.id)
            }
        }
    }
}

private struct DesktopBottomPanel: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @Binding var panelHeight: CGFloat
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 9)
                .overlay {
                    Capsule()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 44, height: 4)
                }
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            if dragStartHeight == nil { dragStartHeight = panelHeight }
                            panelHeight = min(620, max(150, (dragStartHeight ?? panelHeight) - value.translation.height))
                        }
                        .onEnded { _ in dragStartHeight = nil }
                )
                .onTapGesture(count: 2) { panelHeight = 220 }
            HStack(spacing: 10) {
                Picker(workspace.preferences.tr("面板", "Panel"), selection: $workspace.bottomPanelMode) {
                    ForEach(BottomPanelMode.allCases) { mode in
                        Text(panelTitle(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)
                Spacer()
                Button {
                    workspace.isBottomPanelPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(workspace.preferences.tr("关闭底部面板", "Close bottom panel"))
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            switch workspace.bottomPanelMode {
            case .search:
                WorkspaceSearchPanel(workspace: workspace)
            case .functionList:
                FunctionListPanel(document: document, workspace: workspace)
            case .bookmarks:
                BookmarkPanel(document: document, workspace: workspace)
            case .statistics:
                DocumentInfoPanel(document: document, preferences: workspace.preferences)
            case .jsonPath:
                JSONPathPanel(document: document, workspace: workspace)
            case .jsonTree:
                JSONTreePanel(document: document, workspace: workspace)
            case .jsonTools:
                JSONToolsPanel(document: document, workspace: workspace)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func panelTitle(_ mode: BottomPanelMode) -> String {
        switch mode {
        case .search: workspace.preferences.tr("文件查找", "Find in Files")
        case .functionList: workspace.preferences.tr("函数列表", "Function List")
        case .bookmarks: workspace.preferences.tr("书签", "Bookmarks")
        case .statistics: workspace.preferences.tr("文档信息", "Document Info")
        case .jsonPath: "JSONPath"
        case .jsonTree: workspace.preferences.tr("JSON 树", "JSON Tree")
        case .jsonTools: workspace.preferences.tr("JSON 工具", "JSON Tools")
        }
    }
}

private struct FunctionListPanel: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @State private var filter = ""
    @State private var symbols: [FunctionListSymbol] = []
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField(
                    workspace.preferences.tr("筛选符号…", "Filter symbols…"),
                    text: $filter
                )
                .textFieldStyle(.roundedBorder)
                Text(workspace.preferences.tr("\(filteredSymbols.count) 项", "\(filteredSymbols.count) items"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            if filteredSymbols.isEmpty {
                ContentUnavailableView(
                    workspace.preferences.tr("没有符号", "No Symbols"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(workspace.preferences.tr(
                        "当前语言暂无可识别的函数或类型定义。",
                        "No recognizable functions or type definitions for this language."
                    ))
                )
            } else {
                List(filteredSymbols) { symbol in
                    Button {
                        // Prefer the exact symbol offset so the caret lands on
                        // the identifier, not a whole-line selection.
                        let location = min(symbol.utf16Location, (document.content as NSString).length)
                        document.selection = NSRange(location: location, length: 0)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(symbol.name)
                                .font(.body.monospaced())
                                .foregroundStyle(.primary)
                            Spacer(minLength: 8)
                            Text(workspace.preferences.tr("第 \(symbol.line) 行", "Line \(symbol.line)"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(symbol.detail)
                }
                .listStyle(.plain)
            }
        }
        .onAppear { scheduleRefresh() }
        .onChange(of: document.contentRevision) { _, _ in scheduleRefresh() }
        .onChange(of: document.language) { _, _ in scheduleRefresh() }
        .onDisappear { refreshTask?.cancel() }
    }

    private var filteredSymbols: [FunctionListSymbol] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return symbols }
        return symbols.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let text = document.content
        let language = document.language
        let revision = document.contentRevision
        refreshTask = Task(priority: .userInitiated) {
            // Debounce typing so the outline does not re-scan on every key.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let found = FunctionListEngine.symbols(in: text, language: language)
            await MainActor.run {
                guard document.contentRevision == revision else { return }
                symbols = found
            }
        }
    }
}

private struct WorkspaceSearchPanel: View {
    @ObservedObject var workspace: WorkspaceStore
    @State private var showReplaceConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker(workspace.preferences.tr("搜索范围", "Scope"), selection: $workspace.workspaceSearchScope) {
                    Text(workspace.preferences.tr("当前文档", "Current document")).tag(SearchScope.currentDocument)
                    Text(workspace.preferences.tr("所有打开文档", "All open documents")).tag(SearchScope.allOpenDocuments)
                    Text(workspace.preferences.tr("文件夹工作区", "Workspace folder")).tag(SearchScope.workspaceFolder)
                }
                .pickerStyle(.menu)
                .onChange(of: workspace.workspaceSearchScope) { _, _ in workspace.searchWorkspace() }
                TextField(workspace.preferences.tr("在工作区中查找", "Find in workspace folder"), text: $workspace.workspaceSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { workspace.searchWorkspace() }
                Toggle("Aa", isOn: $workspace.workspaceSearchOptions.caseSensitive)
                    .toggleStyle(.button)
                    .help(workspace.preferences.tr("区分大小写", "Match case"))
                Toggle("W", isOn: $workspace.workspaceSearchOptions.wholeWord)
                    .toggleStyle(.button)
                    .disabled(workspace.workspaceSearchOptions.regularExpression)
                    .help(workspace.preferences.tr("全词匹配", "Whole word"))
                Picker("搜索模式", selection: $workspace.workspaceSearchOptions.mode) {
                    Text("普通").tag(SearchMode.normal)
                    Text("扩展").tag(SearchMode.extended)
                    Text("正则表达式").tag(SearchMode.regularExpression)
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
                if workspace.workspaceSearchOptions.regularExpression {
                    Toggle("↵", isOn: $workspace.workspaceSearchOptions.dotMatchesNewline)
                        .toggleStyle(.button)
                        .help(workspace.preferences.tr("点号匹配换行", ". matches newline"))
                }
                Button(workspace.preferences.tr("查找全部", "Find All")) {
                    workspace.searchWorkspace()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(8)

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                TextField(workspace.preferences.tr("替换为", "Replace with"), text: $workspace.workspaceSearchReplacement)
                    .textFieldStyle(.roundedBorder)
                Button("选中文本作为替换") {
                    guard let document = workspace.activeDocument else { return }
                    let text = document.content as NSString
                    let range = document.selection
                    guard range.location != NSNotFound, range.location >= 0,
                          range.location < text.length, range.length > 0 else { return }
                    let safe = NSRange(location: range.location, length: min(range.length, text.length - range.location))
                    workspace.workspaceSearchReplacement = SearchEngine.literalReplacement(
                        text.substring(with: safe), options: workspace.workspaceSearchOptions
                    )
                }
                .buttonStyle(.bordered)
                .disabled((workspace.activeDocument?.selection.length ?? 0) == 0)
                Button("在\(replacementScopeTitle)全部替换…") {
                    showReplaceConfirmation = true
                }
                .buttonStyle(.bordered)
                .disabled(workspace.workspaceSearchQuery.isEmpty)
                .help(workspace.preferences.tr("按当前范围替换；替换前会再次确认；支持正则捕获组 $1、$2", "Replace in the selected scope; confirmation required; regex capture groups $1, $2 are supported"))
                Button(workspace.preferences.tr("清除标记", "Clear marks")) {
                    workspace.clearSearchMarks()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)

            if workspace.workspaceSearchResults.isEmpty {
                ContentUnavailableView(
                    workspace.workspaceSearchQuery.isEmpty
                        ? workspace.preferences.tr("在文件中查找", "Find in Files")
                        : workspace.preferences.tr("没有匹配结果", "No Results"),
                    systemImage: "text.magnifyingglass",
                    description: Text(workspace.workspaceFolder == nil
                                      ? (workspace.workspaceSearchScope == .workspaceFolder
                                         ? workspace.preferences.tr("请先打开文件夹工作区。", "Open a workspace folder, then search every text file.")
                                         : workspace.preferences.tr("输入关键词后执行查找全部。", "Enter a query and choose Find All."))
                                      : workspace.preferences.tr("搜索结果会显示在这里。", "Search results will appear here."))
                )
            } else {
                List(workspace.workspaceSearchResults) { result in
                    Button {
                        workspace.open(searchResult: result)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(result.fileURL.lastPathComponent)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("\(result.line):\(result.column)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.green)
                            highlightedSnippet(result)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .confirmationDialog(
            "确认替换\(replacementScopeTitle)中的全部匹配项？",
            isPresented: $showReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button(workspace.preferences.tr("全部替换", "Replace All"), role: .destructive) {
                workspace.replaceAllInSearchScope()
            }
            Button(workspace.preferences.tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(workspace.preferences.tr("当前范围内的所有匹配项都会被替换；已打开文档会保留为未保存状态。", "Every match in the selected scope will be replaced; open documents remain unsaved."))
        }
        .onChange(of: workspace.workspaceSearchOptions) { _, _ in
            workspace.searchWorkspace()
        }
    }

    private var replacementScopeTitle: String {
        switch workspace.workspaceSearchScope {
        case .currentDocument: "当前文档"
        case .allOpenDocuments: "所有打开文档"
        case .workspaceFolder: "文件夹工作区"
        }
    }

    private func highlightedSnippet(_ result: WorkspaceSearchResult) -> Text {
        let display = result.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        let attributed = NSMutableAttributedString(string: display, attributes: [
            .foregroundColor: UIColor.secondaryLabel
        ])
        for match in result.snippetMatches {
            let safe = NSIntersectionRange(match, NSRange(location: 0, length: attributed.length))
            if safe.length > 0 {
                attributed.addAttributes([
                    .foregroundColor: UIColor.label,
                    .backgroundColor: UIColor.systemYellow.withAlphaComponent(0.35)
                ], range: safe)
            }
        }
        return Text(AttributedString(attributed))
    }
}

private struct BookmarkPanel: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore

    var body: some View {
        if document.bookmarks.isEmpty {
            ContentUnavailableView(
                workspace.preferences.tr("没有书签", "No Bookmarks"),
                systemImage: "bookmark",
                description: Text(workspace.preferences.tr("在当前行添加书签后，可从此处快速导航。", "Toggle a bookmark on the current line to build a navigation list."))
            )
        } else {
            List(document.bookmarks.sorted(), id: \.self) { line in
                Button {
                    document.goToLine(line)
                } label: {
                    HStack {
                        Image(systemName: "bookmark.fill")
                            .foregroundStyle(.green)
                        Text(workspace.preferences.tr("第 \(line) 行", "Line \(line)"))
                        Spacer()
                        Text(lineSnippet(line))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
    }

    private func lineSnippet(_ line: Int) -> String {
        let lines = document.content.components(separatedBy: "\n")
        guard lines.indices.contains(line - 1) else { return "" }
        return lines[line - 1].trimmingCharacters(in: .whitespaces)
    }
}

private struct DocumentInfoPanel: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var preferences: EditorPreferences

    var body: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 8) {
                infoRow(preferences.tr("文件", "File"), document.fileURL?.path ?? preferences.tr("未保存文档", "Unsaved document"))
                infoRow(preferences.tr("语言", "Language"), preferences.title(for: document.language))
                infoRow(preferences.tr("编码", "Encoding"), document.encoding.displayName)
                infoRow(preferences.tr("换行符", "Line endings"), preferences.title(for: document.lineEnding))
                infoRow(preferences.tr("行数", "Lines"), document.lineCount.formatted())
                infoRow(preferences.tr("词数", "Words"), document.wordCount.formatted())
                infoRow(preferences.tr("字符数", "Characters"), document.characterCount.formatted())
                infoRow(preferences.tr("UTF-8 字节", "UTF-8 bytes"), document.byteCount.formatted())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }
}

private struct JSONPathPanel: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @State private var path = "$"
    @State private var results: [JSONPathMatch] = []
    @State private var error = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("JSONPath，例如 $.items[*].name", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { run() }
                Button("查询") { run() }.buttonStyle(.borderedProminent)
            }.padding(.horizontal, 10).padding(.top, 8)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption).padding(.horizontal, 10) }
            if results.isEmpty && error.isEmpty {
                ContentUnavailableView("暂无结果", systemImage: "point.3.connected.trianglepath.dotted", description: Text("输入路径后查询 JSON 内容"))
            } else {
                List(results) { match in
                    Button { reveal(match) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(match.path).font(.caption.monospaced()).foregroundStyle(.green)
                            Text(Self.display(match.value)).font(.caption.monospaced()).lineLimit(2).foregroundStyle(.primary)
                        }
                    }.buttonStyle(.plain)
                }.listStyle(.plain)
            }
        }
    }
    private func run() {
        do { results = try JSONPathEngine.query(document.content, path: path); error = results.isEmpty ? "未找到匹配节点" : "" }
        catch { results = []; self.error = error.localizedDescription }
    }
    private func reveal(_ match: JSONPathMatch) {
        guard let text = try? JSONSerialization.data(withJSONObject: match.value, options: [.sortedKeys]), let snippet = String(data: text, encoding: .utf8) else { return }
        let range = (document.content as NSString).range(of: snippet)
        guard range.location != NSNotFound else { return }
        document.selection = range
        SearchRevealStore.shared.set(range, for: document.id)
        NotificationCenter.default.post(name: .editorSearchRevealSelection, object: SearchSelectionRequest(documentID: document.id, selection: range))
    }
    private static func display(_ value: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { return text }
        return String(describing: value)
    }
}

private struct JSONTreePanel: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @State private var root: JSONTreeNode?
    @State private var issue = ""

    var body: some View {
        Group {
            if let root {
                List { JSONTreeRow(node: root, document: document) }.listStyle(.sidebar)
            } else { ContentUnavailableView("无法生成 JSON 树", systemImage: "list.bullet.indent", description: Text(issue.isEmpty ? "仅对 JSON 文件启用" : issue)) }
        }
        .onAppear { reload() }
        .onChange(of: document.contentRevision) { _, _ in reload() }
    }
    private func reload() {
        guard let data = document.content.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { root = nil; issue = "JSON 格式错误，请先修复"; return }
        root = JSONTreeNode.make(key: "$", any: object); issue = ""
    }
}

private struct JSONTreeRow: View {
    let node: JSONTreeNode
    @ObservedObject var document: EditorDocument
    var body: some View {
        if node.children.isEmpty {
            Button { reveal(node) } label: { label }.buttonStyle(.plain)
        } else {
            DisclosureGroup { ForEach(node.children) { child in JSONTreeRow(node: child, document: document) } } label: { label }
        }
    }
    private var label: some View { HStack(spacing: 6) { Text(node.key).font(.caption.monospaced()).foregroundStyle(.primary); Text(node.value).font(.caption.monospaced()).foregroundStyle(.secondary) } }
    private func reveal(_ node: JSONTreeNode) {
        let token = node.key == "$" ? "{" : node.key.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let range = (document.content as NSString).range(of: token)
        if range.location != NSNotFound { document.selection = range; SearchRevealStore.shared.set(range, for: document.id); NotificationCenter.default.post(name: .editorSearchRevealSelection, object: SearchSelectionRequest(documentID: document.id, selection: range)) }
    }
}

private struct JSONToolsPanel: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var workspace: WorkspaceStore
    @State private var issue: JSONValidationIssue?
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Button("格式化") { format(pretty: true) }; Button("压缩") { format(pretty: false) }; Button("排序键") { sortKeys() }; Button("校验") { validate() } }.buttonStyle(.bordered)
            HStack { Button("转义") { transform(escape: true) }; Button("反转义") { transform(escape: false) }; Spacer() }
            if let issue { Button { document.goToLine(issue.line) } label: { Label("第 \(issue.line) 行，列 \(issue.column)：\(issue.message)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }.buttonStyle(.plain) }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            Spacer()
        }.padding(12)
        .onReceive(NotificationCenter.default.publisher(for: .jsonValidationRequested)) { notification in
            guard let requestedID = notification.object as? UUID, requestedID == document.id else { return }
            validate()
        }
    }
    private func format(pretty: Bool) {
        do { let data = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: Data(document.content.utf8), options: [.fragmentsAllowed]), options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]); document.content = String(decoding: data, as: UTF8.self); status = pretty ? "已格式化" : "已压缩"; workspace.documentDidChange(document) }
        catch { status = "JSON 格式错误：\(error.localizedDescription)" }
    }
    private func sortKeys() { format(pretty: true) }
    private func validate() { issue = JSONValidator.validate(document.content); status = issue == nil ? "JSON 校验通过" : "发现 JSON 错误" }
    private func transform(escape: Bool) { document.content = escape ? document.content.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") : document.content.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\"); workspace.documentDidChange(document); status = escape ? "已转义" : "已反转义" }
}

private struct MarkdownSplitDivider: View {
    @Binding var ratio: CGFloat
    let totalWidth: CGFloat
    @State private var dragStartRatio: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(width: 1)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.secondary.opacity(0.55))
                .frame(width: 4, height: 42)
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartRatio ?? ratio
                    dragStartRatio = start
                    // The parent clamps the actual pane widths; this ratio
                    // remains stable as the window is resized.
                    ratio = min(0.72, max(0.28, start + value.translation.width / max(totalWidth, 1)))
                }
                .onEnded { _ in dragStartRatio = nil }
        )
        .accessibilityLabel("拖动调整编辑器与预览宽度")
        .help("拖动调整编辑器与预览宽度")
    }
}

private struct MarkdownPreviewPane: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var preferences: EditorPreferences
    @Binding var isFullScreen: Bool
    @State private var previewID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(preferences.tr("Markdown 预览", "Markdown Preview"), systemImage: "eye")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Menu {
                    ForEach(MarkdownPreviewStyle.allCases) { style in
                        Button {
                            preferences.markdownPreviewStyle = style
                        } label: {
                            if preferences.markdownPreviewStyle == style {
                                Label(style.title, systemImage: "checkmark")
                            } else {
                                Label(style.title, systemImage: style.symbolName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paintpalette")
                        Text(preferences.markdownPreviewStyle.title)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .help(preferences.tr("预览风格", "Preview style"))
                .accessibilityLabel(preferences.tr("预览风格", "Preview style"))
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .markdownCopyRequested, object: previewID)
                } label: { Image(systemName: "doc.on.doc").frame(width: 26, height: 24) }
                .buttonStyle(.plain)
                .accessibilityLabel("复制预览")
                .help("复制选中的预览文字；未选中时复制全部预览")
                Button {
                    isFullScreen.toggle()
                } label: {
                    Image(systemName: isFullScreen
                          ? "arrow.down.right.and.arrow.up.left"
                          : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFullScreen ? "退出全屏预览" : "全屏预览")
                .help(isFullScreen ? "退出全屏预览" : "全屏预览")
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            MarkdownPreview(document: document, preferences: preferences, previewID: previewID)
        }
    }
}

private struct MarkdownPreview: UIViewRepresentable {
    @ObservedObject var document: EditorDocument
    @ObservedObject var preferences: EditorPreferences
    let previewID: UUID

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.addUserScript(WKUserScript(
            source: MarkdownPreviewBridge.script, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: .defaultClient
        ))
        configuration.userContentController.add(context.coordinator, contentWorld: .defaultClient, name: "markdownViewport")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.alwaysBounceHorizontal = false
        context.coordinator.attach(webView)
        return webView
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.renderWorkItem?.cancel()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "markdownViewport", contentWorld: .defaultClient)
        webView.navigationDelegate = nil
        coordinator.detach()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let cacheKey = "\(preferences.appearance.rawValue)|\(preferences.markdownPreviewStyle.rawValue)|\(document.content)"
        guard cacheKey != coordinator.lastCacheKey else { return }
        coordinator.lastCacheKey = cacheKey
        coordinator.renderWorkItem?.cancel()
        let source = document.content
        let theme: String
        switch preferences.appearance {
        case .light, .github: theme = "light"
        case .system: theme = "system"
        default: theme = "dark"
        }
        let style = preferences.markdownPreviewStyle.rawValue
        let emptyMessage = preferences.tr("开始输入 Markdown 后，预览会实时显示在这里。", "Start typing Markdown to see the live preview.")
        let workItem = DispatchWorkItem { [weak coordinator] in
            let html = MarkdownHTMLRenderer.render(source, theme: theme, style: style, emptyMessage: emptyMessage)
            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator, coordinator.lastCacheKey == cacheKey else { return }
                coordinator.apply(html: html)
            }
        }
        coordinator.renderWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + (coordinator.hasLoadedContent ? 0.12 : 0), execute: workItem)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownPreview
        weak var webView: WKWebView?
        var lastCacheKey = ""
        var hasLoadedContent = false
        var isLoading = false
        var pendingHTML: String?
        var renderWorkItem: DispatchWorkItem?
        var observers: [NSObjectProtocol] = []

        init(parent: MarkdownPreview) { self.parent = parent }
        deinit {
            renderWorkItem?.cancel()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func detach() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            webView = nil
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            observers.append(NotificationCenter.default.addObserver(forName: .markdownEditorDidScroll, object: nil, queue: .main) { [weak self] notification in
                guard let self, let request = notification.object as? MarkdownScrollRequest,
                      request.documentID == self.parent.document.id else { return }
                self.scroll(to: request.position)
            })
            observers.append(NotificationCenter.default.addObserver(forName: .markdownCopyRequested, object: nil, queue: .main) { [weak self] notification in
                guard let self, notification.object as? UUID == self.parent.previewID else { return }
                self.webView?.evaluateJavaScript("window.notepadMarkdown.copyText()", in: nil, in: .defaultClient) { result in
                    if case .success(let text as String) = result { UIPasteboard.general.string = text }
                }
            })
        }

        func apply(html: String) {
            guard let webView else { return }
            pendingHTML = html
            guard hasLoadedContent else {
                if !isLoading {
                    isLoading = true
                    webView.loadHTMLString(html, baseURL: nil)
                }
                return
            }
            let position = parent.document.markdownScrollPosition ?? MarkdownScrollPosition()
            webView.callAsyncJavaScript("window.notepadMarkdown.update(html, line, progress)",
                arguments: ["html": html, "line": position.sourceLine, "progress": position.progress], in: nil, in: .defaultClient, completionHandler: nil)
        }

        func scroll(to position: MarkdownScrollPosition) {
            guard hasLoadedContent else { return }
            webView?.callAsyncJavaScript("window.notepadMarkdown.scrollToPosition(line, progress)",
                arguments: ["line": position.sourceLine, "progress": position.progress], in: nil, in: .defaultClient, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoading = false
            hasLoadedContent = true
            if let pendingHTML { apply(html: pendingHTML) }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let payload = message.body as? [String: Any],
                  let line = payload["line"] as? Double, let progress = payload["progress"] as? Double,
                  line.isFinite, progress.isFinite else { return }
            let position = MarkdownScrollPosition(sourceLine: line, progress: progress)
            parent.document.markdownScrollPosition = position
            NotificationCenter.default.post(name: .markdownPreviewDidScroll,
                object: MarkdownScrollRequest(documentID: parent.document.id, position: position))
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated {
                if let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}

struct DocumentTabStrip: View {
    @ObservedObject var workspace: WorkspaceStore
    @State private var draggedDocumentID: UUID?

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(workspace.tabDocuments) { document in
                            let groupColor = workspace.documentGroups
                                .first(where: { $0.id == document.groupID })?
                                .color.color ?? .gray
                            DocumentTabButton(
                                document: document,
                                preferences: workspace.preferences,
                                accent: groupColor,
                                isActive: workspace.activeDocumentID == document.id,
                                onSelect: { workspace.activate(document) },
                                onClose: { NotificationCenter.default.post(name: .requestCloseDocument, object: document) },
                                onExit: { NotificationCenter.default.post(name: .requestExitDocument, object: document) },
                                onTogglePin: { workspace.togglePin(document) },
                                onCloseOthers: { workspace.closeUnchangedDocuments(except: document) },
                                onReload: { workspace.reload(document) },
                                onRevealInFinder: { revealDocumentInFinder(document) },
                                onDragStart: { draggedDocumentID = document.id }
                            )
                            .id(document.id)
                            .onDrop(
                                of: [.text],
                                delegate: DocumentTabDropDelegate(
                                    targetID: document.id,
                                    draggedID: $draggedDocumentID,
                                    workspace: workspace
                                )
                            )
                        }
                        Color.clear
                            .frame(minWidth: 72, maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { workspace.newDocument() }
                            .accessibilityLabel("标签栏空白区域，双击新建文档")
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { workspace.newDocument() }
                            .id("tab-strip-end")
                    }
                    .padding(.horizontal, 4)
                    .frame(minWidth: geometry.size.width, maxHeight: .infinity, alignment: .leading)
                }
                .onAppear {
                    scrollTabStrip(proxy, preferEnd: true, animated: false)
                }
                .onChange(of: workspace.activeDocumentID) { _, _ in
                    scrollTabStrip(proxy, preferEnd: false, animated: true)
                }
                .onChange(of: workspace.documents.count) { _, _ in
                    // New tabs append on the right — keep the end visible so
                    // close / switch stays within reach.
                    scrollTabStrip(proxy, preferEnd: true, animated: true)
                }
            }
        }
        .frame(height: max(40, workspace.preferences.tabFontSize + 25))
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func scrollTabStrip(_ proxy: ScrollViewProxy, preferEnd: Bool, animated: Bool) {
        let target: AnyHashable
        if preferEnd, let last = workspace.documents.last?.id {
            // Default / after open: keep the right end reachable for close & switch.
            target = last
        } else if let active = workspace.activeDocumentID {
            target = active
        } else if let last = workspace.documents.last?.id {
            target = last
        } else {
            target = "tab-strip-end"
        }
        let scroll = { proxy.scrollTo(target, anchor: .trailing) }
        if animated {
            withAnimation(.easeInOut(duration: 0.18), scroll)
        } else {
            // Wait one layout pass so tab widths exist before scrolling.
            DispatchQueue.main.async(execute: scroll)
        }
    }
}

private struct DocumentTabButton: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var preferences: EditorPreferences
    /// The document inherits its group's colour so the relationship remains
    /// visible in the tab strip as well as in the sidebar.
    let accent: Color
    let isActive: Bool
    let onSelect: () -> Void
    /// Hide from the tab strip; keep the document in 文档导航.
    let onClose: () -> Void
    /// Remove from tabs and 文档导航.
    let onExit: () -> Void
    let onTogglePin: () -> Void
    let onCloseOthers: () -> Void
    let onReload: () -> Void
    let onRevealInFinder: () -> Void
    let onDragStart: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.caption)
                    .foregroundStyle(isActive ? accent : accent.opacity(0.78))
                if document.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(document.title)
                    .font(.system(size: preferences.tabFontSize, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? accent : .primary)
                    .lineLimit(1)
                if document.isDirty {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .accessibilityLabel(preferences.tr("已修改", "Modified"))
                        .help(preferences.tr("文档已修改", "Document modified"))
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(preferences.tr("关闭 \(document.title)", "Close \(document.title)"))
                .help(preferences.tr("关闭 \(document.title)", "Close \(document.title)"))
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: max(36, preferences.tabFontSize + 20))
            .background(isActive ? Color(uiColor: .systemBackground) : Color.clear)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
            .overlay(alignment: .bottom) {
                if isActive {
                    Rectangle().fill(accent).frame(height: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .onDrag {
            onDragStart()
            return NSItemProvider(object: NSString(string: document.id.uuidString))
        }
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contextMenu {
            Button(document.isPinned
                   ? preferences.tr("取消固定", "Unpin")
                   : preferences.tr("固定标签页", "Pin Tab"), action: onTogglePin)
            Button(preferences.tr("关闭其他未修改标签页", "Close Other Unchanged Tabs"), action: onCloseOthers)
            if document.fileURL != nil {
                #if targetEnvironment(macCatalyst)
                Button {
                    onRevealInFinder()
                } label: {
                    Label(
                        preferences.tr("在 Finder 中显示", "Show in Finder"),
                        systemImage: "folder"
                    )
                }
                #endif
                Button(preferences.tr("从磁盘重新载入", "Reload from Disk"), action: onReload)
            }
            Divider()
            Button(preferences.tr("关闭", "Close"), action: onClose)
            Button(preferences.tr("退出", "Exit"), role: .destructive, action: onExit)
        }
    }

    private var iconName: String {
        switch document.language {
        case .markdown: "text.document"
        case .json, .yaml, .xml: "curlybraces"
        case .html, .css: "chevron.left.forwardslash.chevron.right"
        case .plainText: "doc.plaintext"
        default: "terminal"
        }
    }

}

private func revealDocumentInFinder(_ document: EditorDocument) {
    guard let fileURL = document.fileURL else { return }
    #if targetEnvironment(macCatalyst)
    let url = fileURL.standardizedFileURL
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
    // UIApplication.open on the parent folder does not select the file, and
    // inside the sandbox it often fails silently. NSWorkspace's reveal API is
    // what Finder itself uses for "Show in Finder".
    if !FinderReveal.reveal(url) {
        UIApplication.shared.open(url.deletingLastPathComponent(), options: [:], completionHandler: nil)
    }
    #endif
}

#if targetEnvironment(macCatalyst)
/// Mac Catalyst cannot import AppKit, but the system AppKit image is present
/// at runtime. Load it once and call `activateFileViewerSelectingURLs:`, which
/// activates Finder and selects the file. `perform(_:with:)` is not used
/// because that method returns void.
private enum FinderReveal {
    private static let appKitHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW)
    }()

    static func reveal(_ url: URL) -> Bool {
        guard appKitHandle != nil,
              let workspaceClass = NSClassFromString("NSWorkspace") as? NSObject.Type
        else { return false }
        let sharedSelector = NSSelectorFromString("sharedWorkspace")
        guard workspaceClass.responds(to: sharedSelector),
              let shared = workspaceClass.perform(sharedSelector)?.takeUnretainedValue()
        else { return false }
        let selector = NSSelectorFromString("activateFileViewerSelectingURLs:")
        guard let method = class_getInstanceMethod(object_getClass(shared), selector) else { return false }
        typealias RevealIMP = @convention(c) (AnyObject, Selector, NSArray) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: RevealIMP.self)
        function(shared, selector, [url])
        return true
    }
}
#endif

private struct DocumentTabDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedID: UUID?
    let workspace: WorkspaceStore

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetID else { return }
        workspace.moveDocument(draggedID, before: targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }
}

private struct EditorStatusBar: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var preferences: EditorPreferences

    private var position: (line: Int, column: Int) {
        document.lineAndColumn(atUTF16Location: document.selection.location)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(preferences.tr("行 \(position.line)，列 \(position.column)", "Ln \(position.line), Col \(position.column)"))
            separator
            Text(preferences.tr("选择 \(document.selection.length)", "Sel \(document.selection.length)"))
            separator
            Text(preferences.tr("\(document.lineCount) 行", "\(document.lineCount) lines"))
            if preferences.columnMode {
                separator
                Label("列模式", systemImage: "rectangle.split.3x1.fill")
                    .foregroundStyle(.green)
                    .help("列模式已开启：拖动鼠标建立矩形选区")
            }
            Spacer()
            Picker(preferences.tr("换行符", "Line ending"), selection: $document.lineEnding) {
                ForEach(LineEnding.allCases) { ending in
                    Text(preferences.title(for: ending)).tag(ending)
                }
            }
            .labelsHidden()
            .fixedSize()
            separator
            Picker(preferences.tr("编码", "Encoding"), selection: $document.encoding) {
                ForEach(DocumentEncoding.allCases) { encoding in
                    Text(encoding.displayName).tag(encoding)
                }
            }
            .labelsHidden()
            .fixedSize()
            separator
            Picker(preferences.tr("语言", "Language"), selection: $document.language) {
                ForEach(SyntaxLanguage.allCases) { language in
                    Text(preferences.title(for: language)).tag(language)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var separator: some View {
        Divider().frame(height: 14).padding(.horizontal, 8)
    }
}

extension Notification.Name {
    /// Hide the document from the tab strip only.
    static let requestCloseDocument = Notification.Name("NotepadPlus.requestCloseDocument")
    /// Fully remove the document from tabs and 文档导航.
    static let requestExitDocument = Notification.Name("NotepadPlus.requestExitDocument")
}
