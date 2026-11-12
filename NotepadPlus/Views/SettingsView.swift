import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var preferences: EditorPreferences
    var onDismiss: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("语言") {
                    LabeledContent("界面语言", value: "简体中文")
                    Text("菜单、工具栏、导航栏、对话框和编辑器提示统一使用简体中文。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("外观") {
                    Picker("主题", selection: Binding(
                        get: { preferences.appearance },
                        set: { preferences.appearance = $0 }
                    )) {
                        ForEach(EditorAppearance.allCases) { appearance in
                            Text(preferences.title(for: appearance)).tag(appearance)
                        }
                    }
                    if preferences.appearance == .custom {
                        ColorPicker("编辑器背景", selection: Binding(
                            get: { Color(hex: preferences.customBackgroundHex) },
                            set: { preferences.customBackgroundHex = $0.hexString }
                        ), supportsOpacity: false)
                        ColorPicker("编辑器文字", selection: Binding(
                            get: { Color(hex: preferences.customForegroundHex) },
                            set: { preferences.customForegroundHex = $0.hexString }
                        ), supportsOpacity: false)
                        Text("可自定义编辑区背景和文字颜色，设置会自动保存。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Picker("编辑字体", selection: $preferences.fontName) {
                        ForEach(EditorPreferences.editorFonts, id: \.self) { fontName in
                            Text(fontDisplayName(fontName))
                                .font(.custom(fontName, size: 14))
                                .tag(fontName)
                        }
                    }
                    HStack {
                        Text("字体大小")
                        Slider(value: $preferences.fontSize, in: 9...40, step: 1)
                        Text("\(Int(preferences.fontSize)) 磅")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    HStack {
                        Text("标签页文档名")
                        Slider(value: $preferences.tabFontSize, in: 11...20, step: 1)
                        Text("\(Int(preferences.tabFontSize)) 磅")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    HStack {
                        Text("导航栏文档名")
                        Slider(value: $preferences.sidebarDocumentFontSize, in: 11...20, step: 1)
                        Text("\(Int(preferences.sidebarDocumentFontSize)) 磅")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    Text("支持 ⌘+/⌘-，也支持按住 Control 后滚动鼠标或触控板。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("个性化签名") {
                    Toggle("显示个性化签名", isOn: $preferences.signatureEnabled)
                    Picker("切换方式", selection: Binding(
                        get: { preferences.signatureStyle },
                        set: { preferences.signatureStyle = $0 }
                    )) {
                        ForEach(SignatureDisplayStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .disabled(!preferences.signatureEnabled)
                    ColorPicker(
                        "语录颜色",
                        selection: Binding(
                            get: { Color(hex: preferences.signatureColorHex) },
                            set: { preferences.signatureColorHex = $0.hexString }
                        ),
                        supportsOpacity: false
                    )
                    .disabled(!preferences.signatureEnabled)
                    Picker("语录字体", selection: $preferences.signatureFontName) {
                        ForEach(EditorPreferences.signatureFonts, id: \.self) { fontName in
                            Text(fontName).font(.custom(fontName, size: 14)).tag(fontName)
                        }
                    }
                    .disabled(!preferences.signatureEnabled)
                    HStack {
                        Text("语录字号")
                        Slider(value: $preferences.signatureFontSize, in: 11...24, step: 1)
                        Text("\(Int(preferences.signatureFontSize)) 磅")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .disabled(!preferences.signatureEnabled)
                    HStack {
                        Text(speedLabel)
                        Slider(value: $preferences.signatureSpeed, in: 12...80, step: 1)
                        Text("\(Int(preferences.signatureSpeed))")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .disabled(!preferences.signatureEnabled)

                    NavigationLink {
                        SignatureQuotesManagerView(preferences: preferences)
                    } label: {
                        HStack {
                            Label("管理签名语录", systemImage: "rectangle.stack.fill")
                            Spacer()
                            Text("\(preferences.signatureQuotes.count) 条")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("每条语录都会完整展示后再切换下一条：横向滚动扫完整段，百叶窗逐行翻页，打字机逐字打出。关闭“显示”只隐藏标题栏，不会删除列表。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("编辑器") {
                    Toggle("显示行号", isOn: $preferences.showLineNumbers)
                    Toggle("显示空白字符", isOn: $preferences.showWhitespace)
                    Toggle("自动换行", isOn: $preferences.wordWrap)
                    Toggle("保持列模式开启", isOn: $preferences.columnMode)
                    Text("列模式开启后直接拖动即可建立矩形选区；未开启时按住 Option 拖动也可以临时使用。选区支持输入、粘贴、剪切和删除。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper("制表符宽度：\(preferences.tabWidth)", value: $preferences.tabWidth, in: 2...8)
                    Toggle("自动保存已有文件", isOn: $preferences.autoSave)
                }

                Section("键盘") {
                    NavigationLink {
                        ShortcutManagerView(preferences: preferences)
                    } label: {
                        Label("快捷键管理", systemImage: "keyboard")
                    }
                    LabeledContent("已配置功能", value: "\(ShortcutAction.allCases.count) 项")
                    Text("内置常用编辑快捷键，可逐项修改、检测冲突或恢复默认设置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("偏好设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { close() }
                        .help("关闭偏好设置")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(preferences.preferredColorScheme)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }

    private func close() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    private var speedLabel: String {
        switch preferences.signatureStyle {
        case .marquee: "滚动速度"
        case .blinds: "翻页速度"
        case .typewriter: "打字速度"
        }
    }

    private func fontDisplayName(_ fontName: String) -> String {
        fontName == "SFMono-Regular" ? "SF Mono" : fontName
    }
}

/// Table-style list + multiline editor for maintaining many signature quotes.
struct SignatureQuotesManagerView: View {
    @ObservedObject var preferences: EditorPreferences
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var confirmsReset = false
    @State private var draftText = ""
    @State private var isExportPresented = false
    @State private var isImportPresented = false
    @State private var confirmsImportReplace = false
    @State private var pendingImportData: Data?
    @State private var statusMessage: String?
    @State private var exportDocument = SignatureQuotesFileDocument(data: Data())

    private var filteredQuotes: [SignatureQuote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return preferences.signatureQuotes }
        return preferences.signatureQuotes.filter {
            $0.text.localizedStandardContains(query)
        }
    }

    private var selectedQuote: SignatureQuote? {
        guard let selectedID else { return nil }
        return preferences.signatureQuotes.first(where: { $0.id == selectedID })
    }

    var body: some View {
        HStack(spacing: 0) {
            quoteTable
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
            Divider()
            quoteEditor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("签名语录")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    addQuote()
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .help("新增一条签名")

                Button(role: .destructive) {
                    deleteSelected()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(selectedID == nil)
                .help("删除当前选中的签名")

                Menu("导入导出") {
                    Button {
                        exportQuotes()
                    } label: {
                        Label("导出语录…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(preferences.signatureQuotes.isEmpty)

                    Button {
                        isImportPresented = true
                    } label: {
                        Label("导入语录…", systemImage: "square.and.arrow.down")
                    }
                }
                .help("导入或导出 JSON 语录文件")

                Button("恢复默认") { confirmsReset = true }
                    .help("恢复内置默认语录")
            }
        }
        .confirmationDialog("恢复默认语录？", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("恢复默认语录", role: .destructive) {
                preferences.restoreDefaultSignatureQuotes()
                preferences.signatureEnabled = true
                selectedID = preferences.signatureQuotes.first?.id
                syncDraftFromSelection()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前自定义签名会被覆盖为内置语录。已导出的文件不受影响。")
        }
        .confirmationDialog("如何导入语录？", isPresented: $confirmsImportReplace, titleVisibility: .visible) {
            Button("追加到现有列表") {
                applyImport(mode: .append)
            }
            Button("替换全部语录", role: .destructive) {
                applyImport(mode: .replace)
            }
            Button("取消", role: .cancel) {
                pendingImportData = nil
            }
        } message: {
            Text("追加不会删除你现有的语录；替换会用文件内容覆盖当前列表。")
        }
        .fileExporter(
            isPresented: $isExportPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "NotepadPlus-signatures"
        ) { result in
            switch result {
            case .success:
                statusMessage = "已导出 \(preferences.signatureQuotes.count) 条语录"
            case .failure(let error):
                statusMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportPresented,
            allowedContentTypes: [.json, .text, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadImportFile(url)
            case .failure(let error):
                statusMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 10)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                            if self.statusMessage == statusMessage {
                                self.statusMessage = nil
                            }
                        }
                    }
            }
        }
        .searchable(text: $searchText, prompt: "搜索签名内容")
        .onAppear {
            if selectedID == nil {
                selectedID = preferences.signatureQuotes.first?.id
            }
            syncDraftFromSelection()
        }
        .onChange(of: selectedID) { _, _ in
            syncDraftFromSelection()
        }
        .onChange(of: preferences.signatureQuotes.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) {
                self.selectedID = ids.first
                syncDraftFromSelection()
            } else if selectedID == nil {
                selectedID = ids.first
                syncDraftFromSelection()
            }
        }
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }

    private func exportQuotes() {
        do {
            let data = try preferences.exportSignatureQuotesPackage()
            exportDocument = SignatureQuotesFileDocument(data: data)
            isExportPresented = true
        } catch {
            statusMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func loadImportFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            pendingImportData = data
            confirmsImportReplace = true
        } catch {
            statusMessage = "读取文件失败：\(error.localizedDescription)"
        }
    }

    private func applyImport(mode: SignatureQuotesImportMode) {
        guard let pendingImportData else { return }
        do {
            let count = try preferences.importSignatureQuotes(from: pendingImportData, mode: mode)
            selectedID = preferences.signatureQuotes.first?.id
            syncDraftFromSelection()
            statusMessage = mode == .replace
                ? "已替换为 \(preferences.signatureQuotes.count) 条语录"
                : "已导入 \(count) 条（现共 \(preferences.signatureQuotes.count) 条）"
        } catch {
            statusMessage = "导入失败：\(error.localizedDescription)"
        }
        self.pendingImportData = nil
    }

    private var quoteTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("列表")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(preferences.signatureQuotes.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            if filteredQuotes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(preferences.signatureQuotes.isEmpty ? "还没有签名" : "没有匹配结果")
                        .foregroundStyle(.secondary)
                    if preferences.signatureQuotes.isEmpty {
                        Button("新增第一条") { addQuote() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(filteredQuotes.enumerated()), id: \.element.id) { index, quote in
                            let absoluteIndex = preferences.signatureQuotes.firstIndex(where: { $0.id == quote.id }) ?? index
                            Button {
                                selectedID = quote.id
                            } label: {
                                SignatureQuoteRow(
                                    index: absoluteIndex + 1,
                                    quote: quote,
                                    isSelected: quote.id == selectedID
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    preferences.moveSignatureQuote(id: quote.id, by: -1)
                                } label: {
                                    Label("上移", systemImage: "arrow.up")
                                }
                                .disabled(absoluteIndex == 0)

                                Button {
                                    preferences.moveSignatureQuote(id: quote.id, by: 1)
                                } label: {
                                    Label("下移", systemImage: "arrow.down")
                                }
                                .disabled(absoluteIndex >= preferences.signatureQuotes.count - 1)

                                Divider()

                                Button(role: .destructive) {
                                    if selectedID == quote.id {
                                        deleteSelected()
                                    } else {
                                        preferences.removeSignatureQuote(id: quote.id)
                                    }
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var quoteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedQuote == nil ? "编辑器" : "编辑签名")
                    .font(.headline)
                Spacer()
                if selectedQuote != nil {
                    Text("\(draftText.count) 字")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if selectedQuote == nil {
                VStack(spacing: 12) {
                    Text("从左侧选择一条签名，或新增后在此编辑。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button {
                        addQuote()
                    } label: {
                        Label("新增签名", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $draftText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 280, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onChange(of: draftText) { _, newValue in
                        guard let selectedID else { return }
                        // Avoid rewrite loops while syncing selection into the draft.
                        if preferences.signatureQuotes.first(where: { $0.id == selectedID })?.text != newValue {
                            preferences.updateSignatureQuote(id: selectedID, to: newValue)
                        }
                    }

                HStack(spacing: 8) {
                    Button {
                        guard let selectedID else { return }
                        _ = preferences.moveSignatureQuote(id: selectedID, by: -1)
                    } label: {
                        Label("上移", systemImage: "arrow.up")
                    }
                    .disabled(!canMoveSelected(by: -1))

                    Button {
                        guard let selectedID else { return }
                        _ = preferences.moveSignatureQuote(id: selectedID, by: 1)
                    } label: {
                        Label("下移", systemImage: "arrow.down")
                    }
                    .disabled(!canMoveSelected(by: 1))

                    Spacer()
                }
                .buttonStyle(.bordered)

                Text("支持多行长文；标题栏轮播只显示去掉首尾空白后仍非空的内容。右侧可搜索，卡片可右键排序或删除。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func addQuote() {
        preferences.signatureEnabled = true
        let id = preferences.appendSignatureQuote("新签名")
        selectedID = id
        searchText = ""
        syncDraftFromSelection()
    }

    private func deleteSelected() {
        guard let selectedID else { return }
        let quotes = preferences.signatureQuotes
        guard let index = quotes.firstIndex(where: { $0.id == selectedID }) else { return }
        preferences.removeSignatureQuote(id: selectedID)
        let next = quotes.indices.contains(index + 1) ? quotes[index + 1].id
            : (index > 0 ? quotes[index - 1].id : nil)
        self.selectedID = next
        syncDraftFromSelection()
    }

    private func syncDraftFromSelection() {
        draftText = selectedQuote?.text ?? ""
    }

    private func canMoveSelected(by offset: Int) -> Bool {
        guard let selectedID,
              let index = preferences.signatureQuotes.firstIndex(where: { $0.id == selectedID }) else {
            return false
        }
        return preferences.signatureQuotes.indices.contains(index + offset)
    }
}

struct SignatureQuotesFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SignatureQuoteRow: View {
    let index: Int
    let quote: SignatureQuote
    let isSelected: Bool

    private var preview: String {
        let trimmed = quote.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "（空签名）" }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .trailing)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(preview)
                    .font(.body)
                    .lineLimit(3)
                    .foregroundStyle(quote.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                Text("\(quote.text.count) 字")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(uiColor: .tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ShortcutManagerView: View {
    @ObservedObject var preferences: EditorPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var confirmsReset = false

    private var matchingActions: [ShortcutAction] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ShortcutAction.allCases
        }
        return ShortcutAction.allCases.filter {
            $0.title.localizedStandardContains(searchText)
                || preferences.shortcut(for: $0).display.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Label("点击“录制”后直接按下任意键或组合，松开后自动保存。支持方向键、功能键、单独修饰键和连续键，例如 ⌘ + ⌘ 或 ⌥ + ⌘。", systemImage: "keyboard.badge.ellipsis")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ForEach(ShortcutCategory.allCases) { category in
                let actions = matchingActions.filter { $0.category == category }
                if !actions.isEmpty {
                    Section(category.title) {
                        ForEach(actions) { action in
                            ShortcutEditorRow(action: action, preferences: preferences)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索功能或快捷键")
        .navigationTitle("快捷键管理")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("恢复全部默认值") { confirmsReset = true }
                    .help("恢复所有内置快捷键")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("完成") { dismiss() }
                    .help("关闭快捷键管理")
            }
        }
        .confirmationDialog("恢复所有默认快捷键？", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("恢复默认快捷键", role: .destructive) { preferences.resetShortcuts() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前的自定义快捷键会被覆盖。")
        }
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }
}

private struct ShortcutEditorRow: View {
    let action: ShortcutAction
    @ObservedObject var preferences: EditorPreferences
    @State private var isRecording = false
    @State private var capturedKeys: [ShortcutPhysicalKey] = []
    @State private var completionTask: DispatchWorkItem?

    private var binding: ShortcutBinding { preferences.shortcut(for: action) }
    private var conflicts: [ShortcutAction] { preferences.conflictingActions(for: action) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(action.title)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(isRecording ? recordedDisplay : (binding.display.isEmpty ? "未设置" : binding.display))
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(conflicts.isEmpty ? .green : .red)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(width: 150)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        isRecording ? Color.green.opacity(0.12) : Color.secondary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 7)
                    )

                Button(isRecording ? "录制中…" : "录制") {
                    isRecording ? cancelRecording() : startRecording()
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .orange : .green)
                .frame(width: 86)
                .help(isRecording ? "点击取消本次录制" : "录制任意键盘组合")

                Button {
                    cancelRecording()
                    preferences.setShortcut(.init(key: "", modifiers: .none), for: action)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除“\(action.title)”的快捷键")
                .help("清除此项快捷键")

                Button {
                    cancelRecording()
                    preferences.resetShortcut(action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("恢复“\(action.title)”的默认快捷键")
                .help("恢复此项默认快捷键")
            }

            if !conflicts.isEmpty {
                Text("与“\(conflicts.map(\.title).joined(separator: "、"))”冲突")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 3)
        .onDisappear { cancelRecording() }
    }

    private var recordedDisplay: String {
        capturedKeys.isEmpty ? "请按下组合键" : capturedKeys.map(\.label).joined(separator: " + ")
    }

    private func startRecording() {
        capturedKeys = []
        isRecording = true
        KeyboardShortcutMonitor.shared.beginCapture { key in
            guard isRecording else { return }
            capturedKeys.append(key)
            completionTask?.cancel()
            let task = DispatchWorkItem { finishRecording() }
            completionTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72, execute: task)
        }
    }

    private func finishRecording() {
        guard isRecording,
              let newBinding = KeyboardShortcutMonitor.shared.binding(from: capturedKeys)
        else {
            cancelRecording()
            return
        }
        preferences.setShortcut(newBinding, for: action)
        isRecording = false
        completionTask = nil
        KeyboardShortcutMonitor.shared.endCapture()
    }

    private func cancelRecording() {
        completionTask?.cancel()
        completionTask = nil
        isRecording = false
        capturedKeys = []
        KeyboardShortcutMonitor.shared.endCapture()
    }
}
