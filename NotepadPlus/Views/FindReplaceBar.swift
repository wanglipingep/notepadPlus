import SwiftUI

/// Search settings survive closing the bar and switching document tabs.
final class FindReplaceState: ObservableObject {
    @Published var query = ""
    @Published var replacement = ""
    @Published var options = SearchOptions()
    @Published var wrapAround = true
    @Published var focusRequest = UUID()
    var focusesReplacement = false
}

struct FindReplaceBar: View {
    @ObservedObject var document: EditorDocument
    @ObservedObject var preferences: EditorPreferences
    @ObservedObject var state: FindReplaceState
    @Binding var isPresented: Bool
    let onDocumentChange: () -> Void

    @State private var matches: [NSRange] = []
    @State private var currentMatch: NSRange?
    @State private var selectionScope: NSRange?
    @State private var scopeContent: String?
    @State private var pendingCountWorkItem: DispatchWorkItem?
    @State private var message = ""
    @State private var hasError = false
    @FocusState private var focusedField: Field?
    private enum Field { case query, replacement }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchRow
            replacementRow
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { modePicker; searchOptions }
                VStack(alignment: .leading, spacing: 8) { modePicker; searchOptions }
            }
            marksRow
            if !message.isEmpty {
                Text(message).font(.caption)
                    .foregroundStyle(hasError ? Color.red : Color.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10).background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { prepareSearch() }
        .onChange(of: state.focusRequest) { _, _ in prepareSearch() }
        .onChange(of: state.query) { _, _ in currentMatch = nil; scheduleCountUpdate() }
        .onChange(of: state.options) { _, _ in currentMatch = nil; updateCount() }
        .onChange(of: selectionScope) { _, _ in updateCount(clearMessage: false) }
        .onChange(of: document.id) { _, _ in
            selectionScope = nil
            scopeContent = nil
            currentMatch = nil
            updateCount()
        }
        .onChange(of: document.selection) { _, selection in
            if selection != currentMatch { currentMatch = nil }
        }
        .onChange(of: document.content) { old, new in
            if scopeContent != new { currentMatch = nil }
            updateSelectionScope(from: old, to: new)
            scheduleCountUpdate()
        }
        .onKeyPress(.escape) { isPresented = false; return .handled }
        .onDisappear {
            pendingCountWorkItem?.cancel()
            NotificationCenter.default.post(
                name: .editorSearchHighlightsChanged,
                object: SearchHighlightRequest(documentID: document.id, ranges: [])
            )
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(preferences.tr("查找", "Find"), text: $state.query)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .query)
                .onSubmit(findNext)
                .onKeyPress(KeyEquivalent.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    findPrevious()
                    return .handled
                }
            Button {
                fillQueryFromSelection()
                updateCount()
                focusedField = .query
            } label: { Image(systemName: "text.cursor") }
            .disabled(selectedText == nil)
            .accessibilityLabel("选中文本用于查找")
            .help("选中文本用于查找")
            Text(matchStatus)
                .font(.caption.monospacedDigit()).frame(minWidth: 58)
                .help("当前匹配 / 匹配总数")
            Button(action: findPrevious) { Image(systemName: "chevron.up") }
                .disabled(matches.isEmpty)
                .help("上一个匹配项（Shift+Enter）")
                .accessibilityLabel("上一个匹配项")
            Button(action: findNext) { Image(systemName: "chevron.down") }
                .disabled(matches.isEmpty)
                .help("下一个匹配项（Enter）")
                .accessibilityLabel("下一个匹配项")
            Menu {
                Button(selectionScope == nil ? "当前文档" : "当前选区") { postSearchAll(scope: .currentDocument) }
                if selectionScope == nil {
                    Button("所有打开文档") { postSearchAll(scope: .allOpenDocuments) }
                    Button("文件夹工作区") { postSearchAll(scope: .workspaceFolder) }
                }
            } label: {
                Label("查找全部", systemImage: "list.bullet.rectangle")
            }
            .disabled(state.query.isEmpty || hasError)
            .help("按当前选区、文档或文件夹范围列出全部匹配项")
            Button { isPresented = false } label: { Image(systemName: "xmark") }
                .accessibilityLabel("关闭查找").help("关闭查找栏（Esc）")
        }
    }

    private var replacementRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            TextField("替换为（留空可删除匹配内容）", text: $state.replacement)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .replacement)
                .onSubmit(replaceCurrent)
            Button {
                guard let text = selectedText else { return }
                state.replacement = SearchEngine.literalReplacement(text, options: state.options)
                focusedField = .replacement
                message = "已将选中文本填入替换框"
            } label: {
                Label("选中文本作为替换", systemImage: "text.badge.plus")
            }
            .buttonStyle(.bordered).disabled(selectedText == nil)
            .help("先在编辑器中选中文字，再点击此按钮；特殊字符会按原文替换")
            Button("替换", action: replaceCurrent)
                .buttonStyle(.bordered).disabled(state.query.isEmpty || hasError)
            Button("全部替换", action: replaceAll)
                .buttonStyle(.borderedProminent).tint(.green)
                .disabled(state.query.isEmpty || hasError)
        }
    }

    private var marksRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(
                    name: .markAllSearchRequested,
                    object: MarkAllRequest(query: state.query, options: state.options, range: selectionScope)
                )
            } label: { Label("标记全部", systemImage: "bookmark") }
            .buttonStyle(.bordered).disabled(matches.isEmpty)
            Button {
                NotificationCenter.default.post(name: .clearSearchMarksRequested, object: nil)
            } label: { Label("清除标记", systemImage: "bookmark.slash") }
            .buttonStyle(.bordered)
            if let selectionScope {
                Text("限定选区：\(selectionScope.length) 字符").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.options.regularExpression {
                Text(#"捕获组：$1、\1、${1}、$+{name}；换行：\n"#)
                    .font(.caption).foregroundStyle(.secondary)
                    .help("使用 Apple ICU 正则引擎；支持常用捕获组、前后查找和行首行尾匹配。Boost 特有语法与条件替换暂不支持。")
            } else if state.options.mode == .extended {
                Text(#"转义字符：\n、\r、\t、\\、\xHH、\uHHHH"#)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var modePicker: some View {
        Picker("搜索模式", selection: $state.options.mode) {
            Text("普通").tag(SearchMode.normal)
            Text("扩展").tag(SearchMode.extended)
            Text("正则表达式").tag(SearchMode.regularExpression)
        }
        .pickerStyle(.segmented).frame(width: 260)
    }

    private var searchOptions: some View {
        HStack(spacing: 10) {
            Toggle("区分大小写", isOn: $state.options.caseSensitive)
            Toggle("全词匹配", isOn: $state.options.wholeWord)
                .disabled(state.options.regularExpression)
            Toggle("循环查找", isOn: $state.wrapAround)
            Toggle("在选区中", isOn: Binding(
                get: { selectionScope != nil },
                set: { selectionScope = $0 ? validSelection : nil }
            ))
            .disabled(selectionScope == nil && selectedText == nil)
            .help("先选中要处理的区域再开启；查找、计数、标记和替换限定在该区域内")
            if state.options.regularExpression {
                Toggle("点号匹配换行", isOn: $state.options.dotMatchesNewline)
            }
        }
        .toggleStyle(.button).font(.callout)
    }

    private var validSelection: NSRange? {
        let length = (document.content as NSString).length
        let range = document.selection
        guard range.location != NSNotFound, range.location >= 0, range.location < length, range.length > 0 else { return nil }
        return NSRange(location: range.location, length: min(range.length, length - range.location))
    }

    private var selectedText: String? {
        validSelection.map { (document.content as NSString).substring(with: $0) }
    }

    private func fillQueryFromSelection() {
        guard let text = selectedText else { return }
        if state.options.regularExpression {
            state.query = NSRegularExpression.escapedPattern(for: text)
        } else if state.options.mode == .extended || text.contains(where: \.isNewline) {
            state.options.mode = .extended
            state.query = SearchEngine.literalReplacement(text, options: state.options)
        } else {
            state.query = text
        }
    }

    private func prepareSearch() {
        // Cmd+H preserves the query, allowing a different selection to supply
        // the replacement through the explicit selection button.
        if !state.focusesReplacement || state.query.isEmpty { fillQueryFromSelection() }
        updateCount()
        DispatchQueue.main.async {
            focusedField = state.focusesReplacement ? .replacement : .query
        }
    }

    private func updateCount(clearMessage: Bool = true) {
        pendingCountWorkItem?.cancel()
        do {
            matches = try SearchEngine.matches(
                in: document.content, query: state.query, options: state.options, in: selectionScope
            )
            hasError = false
            if clearMessage { message = "" }
        } catch {
            matches = []
            hasError = true
            message = "正则表达式无效：\(error.localizedDescription)"
        }
        NotificationCenter.default.post(
            name: .editorSearchHighlightsChanged,
            object: SearchHighlightRequest(
                documentID: document.id,
                ranges: matches,
                currentRange: currentMatch
            )
        )
    }

    private func scheduleCountUpdate() {
        pendingCountWorkItem?.cancel()
        let work = DispatchWorkItem { updateCount(clearMessage: false) }
        pendingCountWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private var matchStatus: String {
        let index = matches.firstIndex(where: { $0 == document.selection && ($0.length > 0 || currentMatch == $0) })
        return "\(index.map { $0 + 1 } ?? 0) / \(matches.count)"
    }

    private func reveal(_ range: NSRange) {
        currentMatch = range
        document.selection = range
        SearchRevealStore.shared.set(range, for: document.id)
        NotificationCenter.default.post(
            name: .editorSearchHighlightsChanged,
            object: SearchHighlightRequest(
                documentID: document.id,
                ranges: matches,
                currentRange: range
            )
        )
        NotificationCenter.default.post(
            name: .editorSearchRevealSelection,
            object: SearchSelectionRequest(documentID: document.id, selection: range)
        )
    }

    private func postSearchAll(scope: SearchScope) {
        NotificationCenter.default.post(
            name: .searchAllRequested,
            object: SearchAllRequest(query: state.query, options: state.options, scope: scope, range: selectionScope)
        )
    }

    private func findNext() { navigate(forward: true) }
    private func findPrevious() { navigate(forward: false) }

    private func navigate(forward: Bool) {
        updateCount()
        guard !matches.isEmpty else {
            if !hasError { message = "未找到匹配内容" }
            return
        }
        let current = matches.firstIndex(where: {
            $0 == document.selection && ($0.length > 0 || currentMatch == $0)
        })
        let index: Int?
        if let current {
            let adjacent = current + (forward ? 1 : -1)
            index = matches.indices.contains(adjacent) ? adjacent : nil
        } else if forward {
            index = matches.firstIndex(where: { $0.location >= NSMaxRange(document.selection) })
        } else {
            index = matches.lastIndex(where: { $0.location < document.selection.location })
        }
        if let index {
            reveal(matches[index])
        } else if state.wrapAround {
            reveal(forward ? matches[0] : matches[matches.count - 1])
            message = forward ? "已从开头继续查找" : "已从末尾继续查找"
        } else {
            message = forward ? "已到达查找范围末尾" : "已到达查找范围开头"
        }
    }

    private func replaceCurrent() {
        updateCount()
        guard !hasError else { return }
        guard let target = matches.first(where: {
            $0 == document.selection && ($0.length > 0 || currentMatch == $0)
        }) else { findNext(); return }
        do {
            let result = try SearchEngine.replaceMatch(
                in: document.content, range: target, query: state.query,
                replacement: state.replacement, options: state.options, in: selectionScope
            )
            if result.text != document.content {
                updateSelectionScope(from: document.content, to: result.text)
                scopeContent = result.text
                commitReplacement(result.text, selection: NSRange(location: NSMaxRange(result.replacementRange), length: 0))
            }
            document.selection = NSRange(location: NSMaxRange(result.replacementRange), length: 0)
            currentMatch = nil
            updateCount()
            let end = document.selection.location
            if let next = matches.first(where: { target.length == 0 ? $0.location > end : $0.location >= end }) {
                reveal(next)
            } else if state.wrapAround, let first = matches.first {
                reveal(first)
            }
            message = "已替换 1 处"
        } catch {
            hasError = true
            message = error.localizedDescription
        }
    }

    private func replaceAll() {
        updateCount()
        guard !hasError else { return }
        do {
            let result = try SearchEngine.replaceAll(
                in: document.content, query: state.query, replacement: state.replacement,
                options: state.options, in: selectionScope
            )
            if result.text != document.content {
                let delta = (result.text as NSString).length - (document.content as NSString).length
                if let range = selectionScope {
                    selectionScope = NSRange(location: range.location, length: max(0, range.length + delta))
                }
                scopeContent = result.text
                commitReplacement(result.text, selection: selectionScope ?? NSRange(location: 0, length: 0))
            }
            currentMatch = nil
            updateCount()
            message = "已替换 \(result.count) 处"
        } catch {
            hasError = true
            message = error.localizedDescription
        }
    }

    private func commitReplacement(_ text: String, selection: NSRange) {
        NotificationCenter.default.post(
            name: .editorSearchReplaceText,
            object: SearchReplacementRequest(
                documentID: document.id, originalText: document.content, text: text, selection: selection
            )
        )
        // The editor applies the change synchronously and registers undo.
        // Retain a model fallback while an editor is being attached.
        if document.content != text {
            document.content = text
            document.selection = selection
            onDocumentChange()
        }
    }

    private func updateSelectionScope(from old: String, to new: String) {
        // A programmatic replacement has already updated the scope.
        if scopeContent == new { scopeContent = nil; return }
        guard let range = selectionScope else { return }
        let before = old as NSString, after = new as NSString
        var prefix = 0
        while prefix < min(before.length, after.length), before.character(at: prefix) == after.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < min(before.length, after.length) - prefix,
              before.character(at: before.length - suffix - 1) == after.character(at: after.length - suffix - 1) { suffix += 1 }
        let removedEnd = before.length - suffix
        let insertedEnd = after.length - suffix
        let delta = after.length - before.length
        let start = range.location <= prefix ? range.location : (range.location >= removedEnd ? range.location + delta : prefix)
        let end = NSMaxRange(range) < prefix ? NSMaxRange(range) : (NSMaxRange(range) >= removedEnd ? NSMaxRange(range) + delta : insertedEnd)
        selectionScope = NSRange(location: max(0, start), length: max(0, end - start))
    }
}
