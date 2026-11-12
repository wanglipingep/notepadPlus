import SwiftUI
import UIKit

enum SignatureDisplayStyle: String, CaseIterable, Identifiable {
    case marquee
    case blinds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .marquee: "横向滚动"
        case .blinds: "百叶窗切换"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese

    var id: String { rawValue }
    var title: String { "简体中文" }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: Int

    static let command = ShortcutModifiers(rawValue: 1 << 0)
    static let shift = ShortcutModifiers(rawValue: 1 << 1)
    static let option = ShortcutModifiers(rawValue: 1 << 2)
    static let control = ShortcutModifiers(rawValue: 1 << 3)
    static let none: ShortcutModifiers = []

    static let commandShift: ShortcutModifiers = [.command, .shift]
    static let commandOption: ShortcutModifiers = [.command, .option]
    static let commandControl: ShortcutModifiers = [.command, .control]
    static let commandOptionShift: ShortcutModifiers = [.command, .option, .shift]
    static let controlShift: ShortcutModifiers = [.control, .shift]
    static let optionShift: ShortcutModifiers = [.option, .shift]

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.command) { result.insert(.command) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.option) { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        return result
    }

    var symbol: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rawValue = try? container.decode(Int.self) {
            self.init(rawValue: rawValue)
            return
        }
        let legacy = (try? container.decode(String.self)) ?? "none"
        switch legacy {
        case "command": self = .command
        case "commandShift": self = .commandShift
        case "commandOption": self = .commandOption
        case "commandControl": self = .commandControl
        case "commandOptionShift": self = .commandOptionShift
        case "control": self = .control
        case "controlShift": self = .controlShift
        case "option": self = .option
        case "optionShift": self = .optionShift
        default: self = .none
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ShortcutPhysicalKey: Codable, Equatable, Hashable {
    let code: Int
    let label: String
}

struct ShortcutBinding: Codable, Equatable {
    var key: String
    var modifiers: ShortcutModifiers
    var physicalSequence: [ShortcutPhysicalKey]?

    init(key: String, modifiers: ShortcutModifiers, physicalSequence: [ShortcutPhysicalKey]? = nil) {
        self.key = key
        self.modifiers = modifiers
        self.physicalSequence = physicalSequence
    }

    var normalizedKey: String { key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    var display: String {
        if let physicalSequence, !physicalSequence.isEmpty {
            return physicalSequence.map(\.label).joined(separator: " + ")
        }
        return modifiers.symbol + displayKey
    }

    var keyEquivalent: KeyEquivalent? {
        guard physicalSequence?.isEmpty != false else { return nil }
        switch normalizedKey {
        case "space": return .space
        case "tab": return .tab
        case "return": return .return
        case "escape": return .escape
        case "delete": return .delete
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "home": return .home
        case "end": return .end
        case "pageup": return .pageUp
        case "pagedown": return .pageDown
        default:
            guard normalizedKey.count == 1, let character = normalizedKey.first else { return nil }
            return KeyEquivalent(character)
        }
    }

    private var displayKey: String {
        switch normalizedKey {
        case "space": "空格"
        case "tab": "⇥"
        case "return": "↩"
        case "escape": "Esc"
        case "delete": "⌫"
        case "up": "↑"
        case "down": "↓"
        case "left": "←"
        case "right": "→"
        case "home": "Home"
        case "end": "End"
        case "pageup": "Page Up"
        case "pagedown": "Page Down"
        default: normalizedKey.uppercased()
        }
    }
}

private struct DynamicKeyboardShortcutModifier: ViewModifier {
    let binding: ShortcutBinding

    @ViewBuilder
    func body(content: Content) -> some View {
        if let key = binding.keyEquivalent {
            content.keyboardShortcut(key, modifiers: binding.modifiers.eventModifiers)
        } else {
            content
        }
    }
}

extension View {
    func appKeyboardShortcut(_ binding: ShortcutBinding) -> some View {
        modifier(DynamicKeyboardShortcutModifier(binding: binding))
    }
}

enum ShortcutCategory: String, CaseIterable, Identifiable {
    case file, edit, search, view, line, navigation

    var id: String { rawValue }
    var title: String {
        switch self {
        case .file: "文件"
        case .edit: "编辑"
        case .search: "查找"
        case .view: "视图"
        case .line: "行操作"
        case .navigation: "导航与书签"
        }
    }
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case newDocument, openDocument, saveDocument, saveAs, saveAll, closeDocument
    case find, findInFiles, replace
    case undo, redo, cut, copy, paste, selectAll, selectNextOccurrence
    case duplicateLine, deleteLine, moveLineUp, moveLineDown, toggleComment, indent, outdent
    case goToLine, markdownPreview, toggleColumnMode, toggleSplitEditor, showFunctionList
    case nextTab, previousTab, duplicateTab
    case toggleBookmark, nextBookmark, previousBookmark
    case zoomIn, zoomOut, resetZoom, openShortcutManager

    var id: String { rawValue }
    var defaultBinding: ShortcutBinding {
        switch self {
        case .newDocument: .init(key: "n", modifiers: .command)
        case .openDocument: .init(key: "o", modifiers: .command)
        case .saveDocument: .init(key: "s", modifiers: .command)
        case .saveAs: .init(key: "s", modifiers: .commandShift)
        case .saveAll: .init(key: "s", modifiers: .commandOption)
        case .closeDocument: .init(key: "w", modifiers: .command)
        case .find: .init(key: "f", modifiers: .command)
        case .findInFiles: .init(key: "f", modifiers: .commandShift)
        case .replace: .init(key: "h", modifiers: .command)
        case .undo: .init(key: "z", modifiers: .command)
        case .redo: .init(key: "z", modifiers: .commandShift)
        case .cut: .init(key: "x", modifiers: .command)
        case .copy: .init(key: "c", modifiers: .command)
        case .paste: .init(key: "v", modifiers: .command)
        case .selectAll: .init(key: "a", modifiers: .command)
        case .selectNextOccurrence: .init(key: "d", modifiers: .commandControl)
        case .duplicateLine: .init(key: "d", modifiers: .command)
        case .deleteLine: .init(key: "l", modifiers: .commandShift)
        case .moveLineUp: .init(key: "u", modifiers: .commandOption)
        case .moveLineDown: .init(key: "j", modifiers: .commandOption)
        case .toggleComment: .init(key: "/", modifiers: .command)
        case .indent: .init(key: "]", modifiers: .command)
        case .outdent: .init(key: "[", modifiers: .command)
        case .goToLine: .init(key: "l", modifiers: .command)
        case .markdownPreview: .init(key: "m", modifiers: .commandShift)
        case .toggleColumnMode: .init(key: "c", modifiers: .commandOption)
        case .toggleSplitEditor: .init(key: "\\", modifiers: .command)
        case .showFunctionList: .init(key: "f", modifiers: .commandOption)
        case .nextTab: .init(key: "]", modifiers: .commandShift)
        case .previousTab: .init(key: "[", modifiers: .commandShift)
        case .duplicateTab: .init(key: "d", modifiers: .commandOption)
        case .toggleBookmark: .init(key: "b", modifiers: .commandOption)
        case .nextBookmark: .init(key: "n", modifiers: .commandOption)
        case .previousBookmark: .init(key: "p", modifiers: .commandOption)
        case .zoomIn: .init(key: "+", modifiers: .command)
        case .zoomOut: .init(key: "-", modifiers: .command)
        case .resetZoom: .init(key: "0", modifiers: .command)
        case .openShortcutManager: .init(key: ",", modifiers: .commandOption)
        }
    }

    var title: String {
        switch self {
        case .newDocument: "新建文档"
        case .openDocument: "打开文件"
        case .saveDocument: "保存"
        case .saveAs: "另存为"
        case .saveAll: "全部保存"
        case .closeDocument: "关闭当前文档"
        case .find: "查找"
        case .findInFiles: "在文件中查找"
        case .replace: "替换"
        case .undo: "撤销"
        case .redo: "重做"
        case .cut: "剪切"
        case .copy: "复制"
        case .paste: "粘贴"
        case .selectAll: "全选"
        case .selectNextOccurrence: "选择下一个匹配项"
        case .duplicateLine: "复制行"
        case .deleteLine: "删除行"
        case .moveLineUp: "上移行"
        case .moveLineDown: "下移行"
        case .toggleComment: "切换注释"
        case .indent: "缩进"
        case .outdent: "反缩进"
        case .goToLine: "跳转到行"
        case .markdownPreview: "Markdown 预览"
        case .toggleColumnMode: "切换列模式"
        case .toggleSplitEditor: "切换分栏编辑"
        case .showFunctionList: "函数列表"
        case .nextTab: "下一个标签页"
        case .previousTab: "上一个标签页"
        case .duplicateTab: "复制标签页"
        case .toggleBookmark: "切换书签"
        case .nextBookmark: "下一个书签"
        case .previousBookmark: "上一个书签"
        case .zoomIn: "放大字体"
        case .zoomOut: "缩小字体"
        case .resetZoom: "重置缩放"
        case .openShortcutManager: "打开快捷键管理"
        }
    }

    var category: ShortcutCategory {
        switch self {
        case .newDocument, .openDocument, .saveDocument, .saveAs, .saveAll, .closeDocument:
            .file
        case .undo, .redo, .cut, .copy, .paste, .selectAll, .selectNextOccurrence:
            .edit
        case .find, .findInFiles, .replace:
            .search
        case .markdownPreview, .toggleColumnMode, .toggleSplitEditor, .showFunctionList, .zoomIn, .zoomOut, .resetZoom,
             .openShortcutManager:
            .view
        case .duplicateLine, .deleteLine, .moveLineUp, .moveLineDown, .toggleComment, .indent, .outdent:
            .line
        case .goToLine, .nextTab, .previousTab, .duplicateTab, .toggleBookmark, .nextBookmark,
             .previousBookmark:
            .navigation
        }
    }
}

enum EditorAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case obsidian
    case dracula
    case nord
    case solarized
    case monokai
    case github
    case custom

    var id: String { rawValue }

}

/// Items that may be shown in the compact editor command bar.  The order and
/// enabled set are persisted so the toolbar can be tailored to each workflow.
enum EditorToolbarItem: String, CaseIterable, Codable, Identifiable {
    case columnMode
    case find
    case findInFiles
    case splitEditor
    case markdownPreview
    case commandPalette
    case functionList
    case fileSearch
    case snippets
    case clipboardHistory
    case font
    case fontSize
    case lineSpacing
    case alignment
    case wordWrap
    case lineNumbers
    case whitespace
    case bookmark
    case more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .columnMode: "列模式"
        case .find: "查询"
        case .findInFiles: "文件查询"
        case .splitEditor: "左右分栏"
        case .markdownPreview: "Markdown 预览"
        case .commandPalette: "命令面板"
        case .functionList: "函数列表"
        case .fileSearch: "搜索文件"
        case .snippets: "代码片段"
        case .clipboardHistory: "剪贴板历史"
        case .font: "字体"
        case .fontSize: "字体大小"
        case .lineSpacing: "行间距"
        case .alignment: "对齐"
        case .wordWrap: "自动换行"
        case .lineNumbers: "显示行号"
        case .whitespace: "显示空白字符"
        case .bookmark: "书签"
        case .more: "更多操作"
        }
    }

    var icon: String {
        switch self {
        case .columnMode: "rectangle.split.3x1"
        case .find: "magnifyingglass"
        case .findInFiles: "folder.badge.magnifyingglass"
        case .splitEditor: "rectangle.split.2x1"
        case .markdownPreview: "text.document"
        case .commandPalette: "command.square"
        case .functionList: "list.bullet.rectangle"
        case .fileSearch: "doc.text.magnifyingglass"
        case .snippets: "text.badge.plus"
        case .clipboardHistory: "clipboard"
        case .font: "textformat"
        case .fontSize: "textformat.size"
        case .lineSpacing: "line.3.horizontal"
        case .alignment: "text.alignleft"
        case .wordWrap: "text.word.spacing"
        case .lineNumbers: "list.number"
        case .whitespace: "rectangle.dashed"
        case .bookmark: "bookmark"
        case .more: "ellipsis.circle"
        }
    }
}

enum EditorTextAlignment: String, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }
    var title: String {
        switch self {
        case .leading: "左对齐"
        case .center: "居中"
        case .trailing: "右对齐"
        }
    }
    var icon: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

final class EditorPreferences: ObservableObject {
    static let editorFonts = ["Menlo", "SFMono-Regular", "Monaco", "Courier New"]
    static let signatureFonts = ["SF Pro Display", "Helvetica Neue", "Menlo", "Monaco", "Georgia"]

    /// Built-in personal signatures.  They are intentionally kept as plain text so users
    /// can replace, remove, or extend them from Preferences without changing the app.
    static let defaultSignatureQuotes: [String] = [
        "星星之火，可以燎原。",
        "一切反动派都是纸老虎。",
        "世上无难事，只要肯登攀。",
        "虚心使人进步，骄傲使人落后。",
        "没有调查，没有发言权。",
        "为人民服务。"
    ]

    @AppStorage("editor.fontSize") var fontSize = 15.0 { willSet { objectWillChange.send() } }
    @AppStorage("editor.fontName") var fontName = "Menlo" { willSet { objectWillChange.send() } }
    @AppStorage("editor.tabFontSize") var tabFontSize = 14.0 { willSet { objectWillChange.send() } }
    @AppStorage("editor.sidebarDocumentFontSize") var sidebarDocumentFontSize = 14.0 { willSet { objectWillChange.send() } }
    @AppStorage("editor.columnMode") var columnMode = false { willSet { objectWillChange.send() } }
    @AppStorage("editor.showLineNumbers") var showLineNumbers = true { willSet { objectWillChange.send() } }
    /// Draw lightweight whitespace markers (middle dots for spaces and arrows for tabs)
    /// without changing the document text or TextKit layout.
    @AppStorage("editor.showWhitespace") var showWhitespace = false { willSet { objectWillChange.send() } }
    @AppStorage("editor.wordWrap") var wordWrap = false { willSet { objectWillChange.send() } }
    @AppStorage("editor.lineSpacing") var lineSpacing = 0.0 { willSet { objectWillChange.send() } }
    @AppStorage("editor.textAlignment") private var textAlignmentRaw = EditorTextAlignment.leading.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("editor.tabWidth") var tabWidth = 4 { willSet { objectWillChange.send() } }
    @AppStorage("editor.autoSave") var autoSave = true { willSet { objectWillChange.send() } }
    @AppStorage("app.language") private var languageRaw = AppLanguage.chinese.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("editor.shortcuts") private var shortcutsJSON = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("editor.appearance") private var appearanceRaw = EditorAppearance.system.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("editor.customBackgroundHex") var customBackgroundHex = "#20242B" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("editor.customForegroundHex") var customForegroundHex = "#E6EDF3" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("personalization.signatureEnabled") var signatureEnabled = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("personalization.signatureQuotes") private var signatureQuotesJSON = "" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("editor.toolbarItems") private var toolbarItemsJSON = "" {
        willSet { objectWillChange.send() }
    }

    static let defaultToolbarItems: [EditorToolbarItem] = [
        // Keep the editor's typography controls at the leading edge of the
        // right-hand command bar.  These are the controls users reach for
        // most often while reading and editing, so they should be visible
        // before navigation and preview actions in the default layout.
        .font, .fontSize, .lineSpacing, .alignment,
        .columnMode, .find, .splitEditor, .markdownPreview, .commandPalette,
        .functionList, .fileSearch, .snippets, .clipboardHistory
    ]
    @AppStorage("personalization.signatureStyle") private var signatureStyleRaw = SignatureDisplayStyle.marquee.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("personalization.signatureColorHex") var signatureColorHex = "#B8C4D6" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("personalization.signatureFontName") var signatureFontName = "SF Pro Display" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("personalization.signatureFontSize") var signatureFontSize = 14.0 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("personalization.signatureSpeed") var signatureSpeed = 34.0 {
        willSet { objectWillChange.send() }
    }

    init() {
        if shortcutsJSON.isEmpty {
            resetShortcuts()
        }
        // Seed the editable list once.  An explicitly empty list is preserved, so users
        // can turn the ticker into a quiet area without the defaults being reintroduced.
        if signatureQuotesJSON.isEmpty {
            signatureQuotes = Self.defaultSignatureQuotes
        }
        if languageRaw != AppLanguage.chinese.rawValue {
            languageRaw = AppLanguage.chinese.rawValue
        }
    }

    /// User-maintained signature list shown in the document command bar.
    var signatureQuotes: [String] {
        get {
            guard let data = signatureQuotesJSON.data(using: .utf8),
                  let values = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return values
        }
        set {
            let cleaned = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let data = try? JSONEncoder().encode(cleaned),
                  let value = String(data: data, encoding: .utf8) else { return }
            signatureQuotesJSON = value
        }
    }

    var textAlignment: EditorTextAlignment {
        get { EditorTextAlignment(rawValue: textAlignmentRaw) ?? .leading }
        set { textAlignmentRaw = newValue.rawValue }
    }

    /// Toolbar order is user configurable.  Unknown values are ignored so a
    /// future build can safely remove an item without breaking preferences.
    var toolbarItems: [EditorToolbarItem] {
        get {
            guard let data = toolbarItemsJSON.data(using: .utf8),
                  let values = try? JSONDecoder().decode([EditorToolbarItem].self, from: data),
                  !values.isEmpty else { return Self.defaultToolbarItems }
            // Older builds persisted a five-item toolbar before typography
            // controls were introduced.  Add the new controls at the front
            // when loading that preference so an existing installation gets
            // the same useful default layout without resetting the user's
            // remaining toolbar choices.
            let leadingControls: [EditorToolbarItem] = [.font, .fontSize, .lineSpacing, .alignment]
            let helperControls: [EditorToolbarItem] = [.functionList, .fileSearch, .snippets, .clipboardHistory]
            // Move typography to the front; append helper tools if an older
            // preference JSON never saved them.
            let leading = leadingControls
            let remainder = values.filter { !leadingControls.contains($0) }
            let missingHelpers = helperControls.filter { !remainder.contains($0) && !leading.contains($0) }
            return leading + remainder + missingHelpers
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let value = String(data: data, encoding: .utf8) else { return }
            toolbarItemsJSON = value
        }
    }

    func resetToolbarItems() {
        toolbarItemsJSON = ""
        objectWillChange.send()
    }

    func appendSignatureQuote(_ quote: String = "") {
        var values = signatureQuotes
        values.append(quote)
        signatureQuotes = values
    }

    func updateSignatureQuote(at index: Int, to quote: String) {
        var values = signatureQuotes
        guard values.indices.contains(index) else { return }
        values[index] = quote
        signatureQuotes = values
    }

    func removeSignatureQuote(at index: Int) {
        var values = signatureQuotes
        guard values.indices.contains(index) else { return }
        values.remove(at: index)
        signatureQuotes = values
    }

    func restoreDefaultSignatureQuotes() {
        signatureQuotes = Self.defaultSignatureQuotes
    }

    var signatureStyle: SignatureDisplayStyle {
        get { SignatureDisplayStyle(rawValue: signatureStyleRaw) ?? .marquee }
        set { signatureStyleRaw = newValue.rawValue }
    }

    var signatureColor: Color { Color(hex: signatureColorHex) }

    var appearance: EditorAppearance {
        get { EditorAppearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var interfaceLanguage: AppLanguage {
        get { .chinese }
        set { languageRaw = AppLanguage.chinese.rawValue }
    }

    func tr(_ chinese: String, _ english: String) -> String {
        chinese
    }

    func title(for appearance: EditorAppearance) -> String {
        switch appearance {
        case .system: tr("跟随系统", "Follow System")
        case .light: tr("浅色", "Light")
        case .dark: tr("深色", "Dark")
        case .obsidian: tr("曜石黑", "Obsidian")
        case .dracula: tr("Dracula 紫夜", "Dracula")
        case .nord: tr("Nord 雪原", "Nord")
        case .solarized: tr("Solarized", "Solarized")
        case .monokai: tr("Monokai", "Monokai")
        case .github: tr("GitHub", "GitHub")
        case .custom: tr("自定义", "Custom")
        }
    }

    var themeBackgroundColor: Color { Color(hex: customBackgroundHexForAppearance) }
    var themeForegroundColor: Color { Color(hex: customForegroundHexForAppearance) }

    private var customBackgroundHexForAppearance: String {
        switch appearance {
        case .system: "#FFFFFF"
        case .light, .github: "#FFFFFF"
        case .dark: "#1D1F24"
        case .obsidian: "#1B1D21"
        case .dracula: "#282A36"
        case .nord: "#2E3440"
        case .solarized: "#002B36"
        case .monokai: "#272822"
        case .custom: customBackgroundHex
        }
    }

    private var customForegroundHexForAppearance: String {
        switch appearance {
        case .system, .light, .github: "#202124"
        case .dark: "#E6E8EC"
        case .obsidian: "#DCE1EA"
        case .dracula: "#F8F8F2"
        case .nord: "#ECEFF4"
        case .solarized: "#EEE8D5"
        case .monokai: "#F8F8F2"
        case .custom: customForegroundHex
        }
    }

    func title(for language: SyntaxLanguage) -> String {
        guard language == .plainText else { return language.displayName }
        return tr("普通文本", "Normal text")
    }

    func title(for lineEnding: LineEnding) -> String {
        switch lineEnding {
        case .lf: tr("Unix（LF）", "Unix (LF)")
        case .crlf: tr("Windows（CR LF）", "Windows (CR LF)")
        case .cr: tr("经典 Mac（CR）", "Classic Mac (CR)")
        }
    }

    func title(for action: LineEditingAction) -> String {
        switch action {
        case .duplicate: tr("复制行", "Duplicate Line")
        case .delete: tr("删除行", "Delete Line")
        case .moveUp: tr("上移行", "Move Line Up")
        case .moveDown: tr("下移行", "Move Line Down")
        case .toggleComment: tr("切换注释", "Toggle Comment")
        case .indent: tr("缩进", "Indent")
        case .outdent: tr("反缩进", "Outdent")
        case .joinWithNext: tr("合并行", "Join Lines")
        case .removeEmptyLines: tr("删除空行", "Remove Empty Lines")
        }
    }

    func title(for transformation: TextTransformation) -> String {
        switch transformation {
        case .uppercase: tr("转换为大写", "UPPERCASE")
        case .lowercase: tr("转换为小写", "lowercase")
        case .capitalize: tr("单词首字母大写", "Capitalize Words")
        case .trimTrailingWhitespace: tr("删除行尾空格", "Trim Trailing Space")
        case .sortLinesAscending: tr("行升序排列 A → Z", "Sort Lines A → Z")
        case .sortLinesDescending: tr("行降序排列 Z → A", "Sort Lines Z → A")
        case .removeDuplicateLines: tr("删除重复行", "Remove Duplicate Lines")
        }
    }

    func shortcut(for action: ShortcutAction) -> ShortcutBinding {
        shortcutMap()[action.rawValue] ?? action.defaultBinding
    }

    func setShortcut(_ binding: ShortcutBinding, for action: ShortcutAction) {
        var map = shortcutMap()
        map[action.rawValue] = ShortcutBinding(
            key: binding.normalizedKey,
            modifiers: binding.modifiers,
            physicalSequence: binding.physicalSequence
        )
        saveShortcutMap(map)
    }

    func action(forPhysicalSequence sequence: [ShortcutPhysicalKey]) -> ShortcutAction? {
        ShortcutAction.allCases.first {
            shortcut(for: $0).physicalSequence?.map(\.code) == sequence.map(\.code)
        }
    }

    func resetShortcut(_ action: ShortcutAction) {
        var map = shortcutMap()
        map[action.rawValue] = action.defaultBinding
        saveShortcutMap(map)
    }

    func resetShortcuts() {
        saveShortcutMap(Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0.rawValue, $0.defaultBinding) }))
    }

    func conflictingActions(for action: ShortcutAction) -> [ShortcutAction] {
        let binding = shortcut(for: action)
        guard !binding.display.isEmpty else { return [] }
        return ShortcutAction.allCases.filter {
            $0 != action && shortcut(for: $0) == binding
        }
    }

    private func shortcutMap() -> [String: ShortcutBinding] {
        guard let data = shortcutsJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: ShortcutBinding].self, from: data)) ?? [:]
    }

    private func saveShortcutMap(_ map: [String: ShortcutBinding]) {
        if let data = try? JSONEncoder().encode(map), let value = String(data: data, encoding: .utf8) {
            shortcutsJSON = value
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark, .obsidian, .dracula, .nord, .solarized, .monokai: .dark
        case .github: .light
        case .custom: Color(hex: customBackgroundHex).isDark ? .dark : .light
        }
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        // Keep sRGB so ColorPicker / chip selections round-trip to the same hex.
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var isDark: Bool {
        #if canImport(UIKit)
        let rgb = rgbaComponents
        return (0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue) < 0.5
        #else
        return true
        #endif
    }

    /// Catalyst `UIColor(Color).getRed` often fails for Display P3 / resolved
    /// picker colors and leaves components at 0 → `#000000`. Convert through
    /// DeviceRGB first so signature / theme pickers keep the chosen swatch.
    var hexString: String {
        let rgb = rgbaComponents
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.red * 255).rounded()),
            Int((rgb.green * 255).rounded()),
            Int((rgb.blue * 255).rounded())
        )
    }

    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        if ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red, green, blue, alpha)
        }
        if let converted = ui.cgColor.converted(
            to: CGColorSpaceCreateDeviceRGB(),
            intent: .defaultIntent,
            options: nil
        ), let comps = converted.components, comps.count >= 3 {
            let alpha = comps.count > 3 ? comps[3] : 1
            return (comps[0], comps[1], comps[2], alpha)
        }
        #endif
        return (0.72, 0.77, 0.84, 1) // fallback ≈ #B8C4D6
    }
}
