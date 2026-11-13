import SwiftUI
import UIKit

enum SignatureDisplayStyle: String, CaseIterable, Identifiable {
    case marquee
    case blinds
    case typewriter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .marquee: "横向滚动"
        case .blinds: "百叶窗（逐行）"
        case .typewriter: "打字机"
        }
    }
}

/// One editable title-bar signature. Stable `id` keeps TextFields alive while
/// the user adds / edits / deletes many quotes.
struct SignatureQuote: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var text: String

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }
}

/// Portable signature list for import / export (JSON).
struct SignatureQuotesPackage: Codable, Equatable {
    var formatVersion: Int
    var app: String
    var exportedAt: String
    var quotes: [SignatureQuote]

    static let currentFormatVersion = 1

    init(quotes: [SignatureQuote], exportedAt: Date = Date()) {
        formatVersion = Self.currentFormatVersion
        app = "NotepadPlus"
        let formatter = ISO8601DateFormatter()
        self.exportedAt = formatter.string(from: exportedAt)
        self.quotes = quotes
    }
}

enum SignatureQuotesImportMode {
    case replace
    case append
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

    /// Built-in personal signatures seeded from the author's maintained quotes.
    static let defaultSignatureQuoteTexts: [String] = [
        "直木成材，弯木成景，人生百态，各有归途，木以不材得终其天年，人以无为而成其有为。论才当向直中取，谋生应从曲中求。",
        "努力是一种行动，坚持是一种态度，努力的人改变了自己，坚持的人改变了命运。知足的人懂得感恩，感恩的人懂得珍惜。想要生活好一点，努力就要多一点，想要过得快乐点，就要知足点",
        "世上无难事，只要肯登攀。",
        """
        心宽一寸，路宽一丈，事缓则圆，人缓则安。
        人生如茶，沉时坦然，浮时淡然。不争是非，方得自在，不较得失，方得圆满。以善待人，以宽处事，以静养心。日子，一半烟火，一半清欢，生活，一半争取，一半随缘。愿你眼里有光，心中有爱，行中有善，不负时光，不负自己。
        """,
        "你一定记住，人生路上不必凡事急于求成，顺其自然，自会遇见美好。古人讲，好事不嫌晚，后登船者先上岸。命运托举你的方式，有时会很惊喜，给你的糖可能会迟到，但从来不会少，该是你的终究会来。好事多磨终成事，只要勇敢向前，前面的路一定是繁花盛开",
        """
        男人的一生，有三样东西不能丢：
        第一是男人顶天立地的骨气。
        第二是成大事的志气。
        第三是善待良人的良心。落魄时，不卑躬屈膝，得志时，不狂妄自大。骨气守住底线，志气指引前路，良心稳住根基。做一个顶天立地的真男人。
        """,
        "风雨送春归，飞雪迎春到。已是悬崖百丈冰，犹有花枝俏。俏也不争春，只把春来报。待到山花烂漫时，她在丛中笑。",
        """
        日出东海落西山，愁也一天，喜也一天；
        认真过好每一天，有也心甘，无也心甘。
        遇事不钻牛角尖，人也舒坦，心也舒坦；
        自古万事难得圆，好也随缘，赖也随缘。
        夫妻本是前世缘，和也是缘，吵也是缘；
        人非圣贤哪得全，睁一只眼，闭一只眼。
        子女上进只能劝，成也自然，败也自然；
        儿孙之福不在爷，有也由天，无也由天。
        少荤多素日三餐，粗也香甜，细也香甜；
        新旧衣服不挑拣，好也御寒，赖也御寒。
        常与知己聊聊天，古也谈谈，今也谈谈；
        内孙外孙同样看，儿也心欢，女也心欢。
        早晚操劳勤锻炼，忙也乐观，闲也乐观；
        心宽体健走人间，不是神仙，胜似神仙。
        """,
        "我本无意惹惊鸿，奈何惊鸿入我心。城南以南不再南，城北以北不再北。春有百花秋有月，夏有凉风冬有雪。若无闲事挂心头，便是人间好时节。野花不种年年有，烦恼无根日日生。愿许秋风知我意，散我心中意难平。",
        """
        自出洞来无敌手，得饶人处且饶人。
        本是青灯不归客，却因浊酒恋红尘。
        一曲清歌满樽酒，人生何处不相逢。
        别有幽愁暗恨生，此时无声胜有声。
        往事不知多少梦，夜来和酒一时醒。
        三生有幸遇见你，纵然悲凉也是情。
        别来半岁音书绝，一寸离肠千万结。
        万丈深渊终有底，唯有人心不可测。
        一生负气成今日，四海无人对夕阳。
        苍天不解人情暖，冷眼看花尽是悲。
        人有生老三千疾，唯有相思不可医。
        前程似锦随风散，从此天涯是路人。
        只缘感君一回顾，使我思君朝与暮。
        天涯地角有穷时，只有相思无尽处。
        人间纵有千百媚，唯独你是情所钟。
        寒灯纸上梨花雨，我等风雪又一年。
        枝上柳绵吹又少，天涯何处无芳草。
        缘来缘去终会散，花开花败总归尘。
        人逢喜事精神爽，闷向心来瞌睡多。
        一世浮生一刹那，一程山水一年华。
        此情应是长相守，你若无心我便休。
        渡尽劫波兄弟在，相逢一笑泯恩仇。
        愿有岁月可回首，且以深情共白头。
        半生风雨半生寒，一杯浊酒敬流年。
        因过竹院逢僧话，偷得浮生半日闲。
        纵是我心红如铁，也难融你千尺冰。
        近水楼台先得月，向阳花木易为春。
        酒不醉人人自醉，色不迷人人自迷。
        君子之交淡如水，小人之交甘若醴。
        一失足成千古恨，再回首是百年身。
        """,
        "儿子是我一生的骄傲，是我满心的欢喜。他人纵有万般好，不及我而一抹笑。他不必完美，不必耀眼，不必成为谁的期待，只愿他健康善良、坦荡，便是我此生最大的心愿。我的儿子是我拼尽全力也要守护的光，是我平淡岁月里最温柔的念想。愿我儿品行端正，无疾无忧，平安顺遂。",
        """
        人生没有如果，命运没有假设，不要尽力而为，而是全力以赴，想要不可代替，就必须与众不同！
        人生如梦，难得一碰，一生朋友一生情，一生有你们才算赢，桌是圆的，菜是咸的，喝酒咱得先敬这请客花钱的。说是从青春到夕阳，一路走来一路忙，远去了风华正茂，迎来了两鬓自霜，愿我们在慢慢变老的路上，拥有着幸福和健康。
        """,
        """
        香烟不解人生苦，烈酒不消世间愁
        茶若醉人何须酒，唯有碎银解千愁
        """,
        "一根烟可以问一条路，一桌酒可以铺一条路。想成功必须要人情世故。小时候老师教我们，先说对不起，然后没关系。长大以后，社会告诉我们，如果你没关系，那只有对不起。烟搭桥，酒铺路，笑脸相迎，人情世故，色作乐，钱挡灾，慷慨送礼后门开，欲攻城池久为兵，道路难行钱作马。万丈红尘三杯酒，千秋大业一壶茶。",
        "你去追鸡，鸡就会跑，要是你手里有把米，鸡就会跟着你，但你千万不要沾沾自喜，因为鸡喜欢的从来不是你，而是你手里的那把米，一旦你把这把米扔出去，那它的眼里就没有你。你扔向哪里，鸡就会跑向哪里，至于那个地方有没有你，鸡一点儿都不关心，你要是把它喂饱了，它就会离你而去，还会到处下蛋。所以，你只能给鸡看，不能给鸡吃。只要你手里有足够多的米，是蒸是煮都有你。所以千万不要高估你在别人心中的位置，鸡爱的是米，而不是你",
        "初见少年拉满弓，不惧岁月不惧风。可终是东风吹醒英雄梦，生活磨平少年心。那一年的少年江湖梦，谁不曾年少轻狂，血气方刚，谁不曾克己复法，胸怀激荡，谁不曾鲜衣怒马，气宇轩昂。年少不知轻狂，总以为自己恰似人间惊鸿客，墨染星辰水云间。后来才发现，奈何人间惊鸿客，只是尘世一俗人。可能人生就是这样，得意时，一日看尽长安花，艰难时，潦倒新停浊酒杯。回首过往半生路，也不过是半生风雨半身伤，半句别恨半心凉。不禁感叹，世事大梦一场，人生几度秋凉。不禁一问，是世间难得，还是我不值？人生本就曲折，前路必定坎坷，谁不是拿最好的青春来换取最深刻的教训呢？既然注定成不了别人世界里的太阳，那就安心做自己世界里的月亮吧",
        "连方丈都背叛了佛祖，而你却始终无法释怀，你真傻，总有一天你会发现，这个世界什么都是假的，而你却认真了一辈子。日落教你告别，大海教你包容，连天地都在循环往复，人又何必执着于非如此不可呢？",
        "如果活着不是为了快乐，那长命百岁还有什么意义呢？在无法重来的人生里，请尽量快乐。凡事看开点儿，日子简单点儿，心头敞亮点儿，风雨由天，快乐由己。记住，首先你要快乐，其他的都是其次。",
        "男人一生最大的财富就是选对妻子，有一个贤惠的妻子，就算你穷困潦倒，她也能陪你东山再起。身材和漂亮这些都不重要，最重要的是这个人的人品，我们归根结底还要跟这个人的人品过一辈子。一个好的妻子可以让我们减去一半的人间疾苦。老话说得好，纵有家财万贯，不如贤妻相伴。家有贤妻旺三代，胜过良田千万顷。",
    ]

    static var defaultSignatureQuotes: [SignatureQuote] {
        defaultSignatureQuoteTexts.map { SignatureQuote(text: $0) }
    }

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
    @AppStorage("editor.markdownPreviewStyle") private var markdownPreviewStyleRaw = MarkdownPreviewStyle.github.rawValue {
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
    /// Published list — `@AppStorage` for this JSON was not reliably refreshing
    /// Settings on Catalyst, and legacy `[String]` storage regenerated UUIDs on
    /// every read (breaking “新增签名” / TextField identity).
    @Published private(set) var signatureQuotes: [SignatureQuote] = []
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
    @AppStorage("personalization.signatureStyle") private var signatureStyleRaw = SignatureDisplayStyle.typewriter.rawValue {
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

    private static let signatureQuotesDefaultsKey = "personalization.signatureQuotes"

    init() {
        if shortcutsJSON.isEmpty {
            resetShortcuts()
        }
        loadSignatureQuotes()
        if languageRaw != AppLanguage.chinese.rawValue {
            languageRaw = AppLanguage.chinese.rawValue
        }
    }

    /// Non-empty texts for the title-bar ticker.
    var activeSignatureTexts: [String] {
        signatureQuotes
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func loadSignatureQuotes() {
        let raw = UserDefaults.standard.string(forKey: Self.signatureQuotesDefaultsKey) ?? ""
        // Empty key → seed defaults once. Explicit `[]` means the user cleared the list.
        if raw.isEmpty {
            signatureQuotes = Self.defaultSignatureQuotes
            persistSignatureQuotes()
            return
        }
        guard let data = raw.data(using: .utf8) else {
            signatureQuotes = Self.defaultSignatureQuotes
            persistSignatureQuotes()
            return
        }
        if let values = try? JSONDecoder().decode([SignatureQuote].self, from: data) {
            signatureQuotes = values
            return
        }
        // Legacy plain string array — migrate once to stable ids and rewrite disk.
        if let legacy = try? JSONDecoder().decode([String].self, from: data) {
            signatureQuotes = legacy.map { SignatureQuote(text: $0) }
            persistSignatureQuotes()
            return
        }
        signatureQuotes = Self.defaultSignatureQuotes
        persistSignatureQuotes()
    }

    private func persistSignatureQuotes() {
        guard let data = try? JSONEncoder().encode(signatureQuotes),
              let value = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(value, forKey: Self.signatureQuotesDefaultsKey)
    }

    private func replaceSignatureQuotes(_ values: [SignatureQuote]) {
        objectWillChange.send()
        signatureQuotes = values
        persistSignatureQuotes()
        // Catalyst Form can miss a single @Published pulse when AppStorage
        // toggles fire in the same run loop — nudge again after persistence.
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
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

    @discardableResult
    func appendSignatureQuote(_ quote: String = "") -> UUID {
        var values = signatureQuotes
        let item = SignatureQuote(text: quote)
        values.append(item)
        replaceSignatureQuotes(values)
        return item.id
    }

    func updateSignatureQuote(id: UUID, to quote: String) {
        var values = signatureQuotes
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].text = quote
        replaceSignatureQuotes(values)
    }

    func removeSignatureQuote(id: UUID) {
        var values = signatureQuotes
        values.removeAll { $0.id == id }
        replaceSignatureQuotes(values)
    }

    func moveSignatureQuotes(from source: IndexSet, to destination: Int) {
        var values = signatureQuotes
        values.move(fromOffsets: source, toOffset: destination)
        replaceSignatureQuotes(values)
    }

    /// Move one quote up (`-1`) or down (`+1`). Returns whether the move applied.
    @discardableResult
    func moveSignatureQuote(id: UUID, by offset: Int) -> Bool {
        guard offset != 0,
              let index = signatureQuotes.firstIndex(where: { $0.id == id }) else { return false }
        let target = index + offset
        guard signatureQuotes.indices.contains(target) else { return false }
        var values = signatureQuotes
        values.swapAt(index, target)
        replaceSignatureQuotes(values)
        return true
    }

    func restoreDefaultSignatureQuotes() {
        replaceSignatureQuotes(Self.defaultSignatureQuotes)
    }

    func exportSignatureQuotesPackage() throws -> Data {
        let package = SignatureQuotesPackage(quotes: signatureQuotes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(package)
    }

    /// Import quotes from a NotepadPlus package or a plain `[SignatureQuote]` /
    /// `[String]` JSON array. Never clears existing quotes unless `mode == .replace`.
    @discardableResult
    func importSignatureQuotes(from data: Data, mode: SignatureQuotesImportMode) throws -> Int {
        let incoming = try Self.decodeSignatureQuotes(from: data)
        guard !incoming.isEmpty else { return 0 }
        switch mode {
        case .replace:
            replaceSignatureQuotes(incoming)
        case .append:
            var merged = signatureQuotes
            let existingTexts = Set(merged.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
            for quote in incoming {
                let trimmed = quote.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { continue }
                if existingTexts.contains(trimmed) { continue }
                merged.append(SignatureQuote(text: quote.text))
            }
            replaceSignatureQuotes(merged)
        }
        signatureEnabled = true
        return incoming.count
    }

    private static func decodeSignatureQuotes(from data: Data) throws -> [SignatureQuote] {
        let decoder = JSONDecoder()
        if let package = try? decoder.decode(SignatureQuotesPackage.self, from: data) {
            return package.quotes
        }
        if let values = try? decoder.decode([SignatureQuote].self, from: data) {
            return values
        }
        if let legacy = try? decoder.decode([String].self, from: data) {
            return legacy.map { SignatureQuote(text: $0) }
        }
        throw NSError(
            domain: "NotepadPlus.SignatureQuotes",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "无法识别的语录文件格式"]
        )
    }

    var signatureStyle: SignatureDisplayStyle {
        get { SignatureDisplayStyle(rawValue: signatureStyleRaw) ?? .typewriter }
        set { signatureStyleRaw = newValue.rawValue }
    }

    var signatureColor: Color { Color(hex: signatureColorHex) }

    var appearance: EditorAppearance {
        get { EditorAppearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var markdownPreviewStyle: MarkdownPreviewStyle {
        get { MarkdownPreviewStyle(rawValue: markdownPreviewStyleRaw) ?? .github }
        set { markdownPreviewStyleRaw = newValue.rawValue }
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
