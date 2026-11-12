import Foundation
import GameController

/// 监听应用前台的物理键盘，用于录制及执行系统菜单无法表示的高级组合。
/// 例如：双击 Command，或只按 Option + Command。
@MainActor
final class KeyboardShortcutMonitor {
    static let shared = KeyboardShortcutMonitor()

    private weak var preferences: EditorPreferences?
    private var actionHandler: ((ShortcutAction) -> Void)?
    private var captureHandler: ((ShortcutPhysicalKey) -> Void)?
    private var recentKeys: [ShortcutPhysicalKey] = []
    private var lastKeyDate = Date.distantPast
    private weak var attachedInput: GCKeyboardInput?

    private init() {}

    func configure(preferences: EditorPreferences, actionHandler: @escaping (ShortcutAction) -> Void) {
        self.preferences = preferences
        self.actionHandler = actionHandler
        attachKeyboardIfNeeded()
    }

    func beginCapture(_ handler: @escaping (ShortcutPhysicalKey) -> Void) {
        captureHandler = handler
        recentKeys = []
        attachKeyboardIfNeeded()
    }

    func endCapture() {
        captureHandler = nil
        recentKeys = []
    }

    func binding(from capturedKeys: [ShortcutPhysicalKey]) -> ShortcutBinding? {
        guard !capturedKeys.isEmpty else { return nil }
        let modifierKeys = capturedKeys.filter { Self.modifier(for: $0.code) != nil }
        let regularKeys = capturedKeys.filter { Self.modifier(for: $0.code) == nil }
        let modifierKinds = modifierKeys.compactMap { Self.modifier(for: $0.code)?.rawValue }
        let hasRepeatedModifier = Set(modifierKinds).count != modifierKinds.count

        if regularKeys.count == 1,
           !hasRepeatedModifier,
           let key = Self.standardKey(for: regularKeys[0].code) {
            let modifiers = modifierKeys.reduce(ShortcutModifiers.none) { partial, key in
                partial.union(Self.modifier(for: key.code)?.shortcutModifier ?? .none)
            }
            return ShortcutBinding(key: key, modifiers: modifiers)
        }

        return ShortcutBinding(key: "", modifiers: .none, physicalSequence: capturedKeys)
    }

    private func attachKeyboardIfNeeded() {
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return }
        guard attachedInput !== input else { return }
        attachedInput = input
        input.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            guard pressed else { return }
            let code = keyCode.rawValue
            Task { @MainActor [weak self] in
                self?.handleKeyDown(code)
            }
        }
    }

    private func handleKeyDown(_ code: Int) {
        let key = ShortcutPhysicalKey(code: code, label: Self.displayName(for: code))
        if let captureHandler {
            captureHandler(key)
            return
        }

        let now = Date()
        if now.timeIntervalSince(lastKeyDate) > 0.9 {
            recentKeys = []
        }
        lastKeyDate = now
        recentKeys.append(key)
        if recentKeys.count > 8 { recentKeys.removeFirst(recentKeys.count - 8) }

        guard let preferences else { return }
        let candidates = ShortcutAction.allCases.compactMap { action -> (ShortcutAction, [ShortcutPhysicalKey])? in
            guard let sequence = preferences.shortcut(for: action).physicalSequence,
                  !sequence.isEmpty
            else { return nil }
            return (action, sequence)
        }.sorted { $0.1.count > $1.1.count }

        for (action, sequence) in candidates where recentKeys.count >= sequence.count {
            let suffix = recentKeys.suffix(sequence.count).map(\.code)
            if suffix == sequence.map(\.code) {
                recentKeys = []
                actionHandler?(action)
                return
            }
        }
    }

    static func displayName(for code: Int) -> String {
        if let modifier = modifier(for: code) { return modifier.symbol }
        if (4...29).contains(code) {
            return String(UnicodeScalar(65 + code - 4)!)
        }
        if (30...38).contains(code) { return String(code - 29) }
        if code == 39 { return "0" }
        return switch code {
        case 40: "↩"
        case 41: "Esc"
        case 42: "⌫"
        case 43: "⇥"
        case 44: "空格"
        case 45: "-"
        case 46: "="
        case 47: "["
        case 48: "]"
        case 49: "\\"
        case 51: ";"
        case 52: "'"
        case 53: "`"
        case 54: ","
        case 55: "."
        case 56: "/"
        case 57: "Caps Lock"
        case 58...69: "F\(code - 57)"
        case 73: "Insert"
        case 74: "Home"
        case 75: "Page Up"
        case 76: "⌦"
        case 77: "End"
        case 78: "Page Down"
        case 79: "→"
        case 80: "←"
        case 81: "↓"
        case 82: "↑"
        default: "Key \(code)"
        }
    }

    private static func standardKey(for code: Int) -> String? {
        if (4...29).contains(code) {
            return String(UnicodeScalar(97 + code - 4)!)
        }
        if (30...38).contains(code) { return String(code - 29) }
        if code == 39 { return "0" }
        return switch code {
        case 40: "return"
        case 41: "escape"
        case 42: "delete"
        case 43: "tab"
        case 44: "space"
        case 45: "-"
        case 46: "="
        case 47: "["
        case 48: "]"
        case 49: "\\"
        case 51: ";"
        case 52: "'"
        case 53: "`"
        case 54: ","
        case 55: "."
        case 56: "/"
        case 74: "home"
        case 75: "pageup"
        case 77: "end"
        case 78: "pagedown"
        case 79: "right"
        case 80: "left"
        case 81: "down"
        case 82: "up"
        default: nil
        }
    }

    private enum ModifierKind: String {
        case control, shift, option, command

        var symbol: String {
            switch self {
            case .control: "⌃"
            case .shift: "⇧"
            case .option: "⌥"
            case .command: "⌘"
            }
        }

        var shortcutModifier: ShortcutModifiers {
            switch self {
            case .control: .control
            case .shift: .shift
            case .option: .option
            case .command: .command
            }
        }
    }

    private static func modifier(for code: Int) -> ModifierKind? {
        switch code {
        case 224, 228: .control
        case 225, 229: .shift
        case 226, 230: .option
        case 227, 231: .command
        default: nil
        }
    }
}
