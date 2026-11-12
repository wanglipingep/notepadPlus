import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: EditorPreferences
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
                    if preferences.signatureEnabled {
                        Picker("切换方式", selection: Binding(
                            get: { preferences.signatureStyle },
                            set: { preferences.signatureStyle = $0 }
                        )) {
                            ForEach(SignatureDisplayStyle.allCases) { style in
                                Text(style.title).tag(style)
                            }
                        }
                        ColorPicker(
                            "语录颜色",
                            selection: Binding(
                                get: { Color(hex: preferences.signatureColorHex) },
                                set: { preferences.signatureColorHex = $0.hexString }
                            ),
                            supportsOpacity: false
                        )
                        Picker("语录字体", selection: $preferences.signatureFontName) {
                            ForEach(EditorPreferences.signatureFonts, id: \.self) { fontName in
                                Text(fontName).font(.custom(fontName, size: 14)).tag(fontName)
                            }
                        }
                        HStack {
                            Text("语录字号")
                            Slider(value: $preferences.signatureFontSize, in: 11...24, step: 1)
                            Text("\(Int(preferences.signatureFontSize)) 磅")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .trailing)
                        }
                        if preferences.signatureStyle == .marquee {
                            HStack {
                                Text("滚动速度")
                                Slider(value: $preferences.signatureSpeed, in: 12...80, step: 1)
                                Text("\(Int(preferences.signatureSpeed))")
                                    .font(.body.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                        }
                        if preferences.signatureQuotes.isEmpty {
                            Text("暂无签名。添加一条语录后，会在顶部标题栏自动轮播。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(preferences.signatureQuotes.enumerated()), id: \.offset) { index, quote in
                                HStack(spacing: 8) {
                                    TextField("签名内容", text: Binding(
                                        get: { quoteAt(index) },
                                        set: { preferences.updateSignatureQuote(at: index, to: $0) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    Button {
                                        preferences.removeSignatureQuote(at: index)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("删除第 \(index + 1) 条签名")
                                }
                            }
                        }
                    }
                    HStack {
                        Button {
                            preferences.appendSignatureQuote()
                        } label: {
                            Label("新增签名", systemImage: "plus")
                        }
                        Button("恢复语录") {
                            preferences.restoreDefaultSignatureQuotes()
                            preferences.signatureEnabled = true
                        }
                    }
                    Text("支持横向跑马灯或百叶窗切换，可自定义颜色、字体、字号和速度。关闭开关即可隐藏，不会删除已保存的内容。")
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
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .help("关闭偏好设置")
                }
            }
        }
        .frame(minWidth: 660, minHeight: 650)
        .preferredColorScheme(preferences.preferredColorScheme)
        .environment(\.locale, Locale(identifier: "zh-Hans"))
    }

    private func fontDisplayName(_ fontName: String) -> String {
        fontName == "SFMono-Regular" ? "SF Mono" : fontName
    }

    private func quoteAt(_ index: Int) -> String {
        guard preferences.signatureQuotes.indices.contains(index) else { return "" }
        return preferences.signatureQuotes[index]
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
