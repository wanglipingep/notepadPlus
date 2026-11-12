import UIKit

struct EditorPalette {
    let background: UIColor
    let foreground: UIColor
    let gutterBackground: UIColor
    let gutterForeground: UIColor
    let keyword: UIColor
    let string: UIColor
    let number: UIColor
    let comment: UIColor
    let type: UIColor
    let tag: UIColor

    static func resolve(
        appearance: EditorAppearance,
        traits: UITraitCollection,
        customBackgroundHex: String? = nil,
        customForegroundHex: String? = nil
    ) -> EditorPalette {
        let isDark = appearance == .dark
            || appearance == .obsidian
            || (appearance == .system && traits.userInterfaceStyle == .dark)

        if appearance == .obsidian || appearance == .dracula || appearance == .nord || appearance == .solarized || appearance == .monokai {
            let palette: EditorPalette
            if appearance == .dracula {
                palette = EditorPalette(background: UIColor(hex: "#282A36"), foreground: UIColor(hex: "#F8F8F2"), gutterBackground: UIColor(hex: "#20212B"), gutterForeground: UIColor(hex: "#6272A4"), keyword: UIColor(hex: "#FF79C6"), string: UIColor(hex: "#F1FA8C"), number: UIColor(hex: "#BD93F9"), comment: UIColor(hex: "#6272A4"), type: UIColor(hex: "#8BE9FD"), tag: UIColor(hex: "#FF5555"))
            } else if appearance == .nord {
                palette = EditorPalette(background: UIColor(hex: "#2E3440"), foreground: UIColor(hex: "#ECEFF4"), gutterBackground: UIColor(hex: "#272C36"), gutterForeground: UIColor(hex: "#616E88"), keyword: UIColor(hex: "#81A1C1"), string: UIColor(hex: "#A3BE8C"), number: UIColor(hex: "#B48EAD"), comment: UIColor(hex: "#616E88"), type: UIColor(hex: "#88C0D0"), tag: UIColor(hex: "#BF616A"))
            } else if appearance == .solarized {
                palette = EditorPalette(background: UIColor(hex: "#002B36"), foreground: UIColor(hex: "#EEE8D5"), gutterBackground: UIColor(hex: "#073642"), gutterForeground: UIColor(hex: "#657B83"), keyword: UIColor(hex: "#859900"), string: UIColor(hex: "#2AA198"), number: UIColor(hex: "#D33682"), comment: UIColor(hex: "#657B83"), type: UIColor(hex: "#B58900"), tag: UIColor(hex: "#CB4B16"))
            } else if appearance == .monokai {
                palette = EditorPalette(background: UIColor(hex: "#272822"), foreground: UIColor(hex: "#F8F8F2"), gutterBackground: UIColor(hex: "#1F201B"), gutterForeground: UIColor(hex: "#75715E"), keyword: UIColor(hex: "#F92672"), string: UIColor(hex: "#E6DB74"), number: UIColor(hex: "#AE81FF"), comment: UIColor(hex: "#75715E"), type: UIColor(hex: "#66D9EF"), tag: UIColor(hex: "#A6E22E"))
            } else {
                palette = EditorPalette(
                background: UIColor(red: 0.105, green: 0.113, blue: 0.129, alpha: 1),
                foreground: UIColor(red: 0.86, green: 0.88, blue: 0.91, alpha: 1),
                gutterBackground: UIColor(red: 0.075, green: 0.082, blue: 0.095, alpha: 1),
                gutterForeground: UIColor(red: 0.42, green: 0.46, blue: 0.52, alpha: 1),
                keyword: UIColor(red: 0.78, green: 0.52, blue: 0.98, alpha: 1),
                string: UIColor(red: 0.66, green: 0.86, blue: 0.54, alpha: 1),
                number: UIColor(red: 0.95, green: 0.68, blue: 0.39, alpha: 1),
                comment: UIColor(red: 0.42, green: 0.56, blue: 0.43, alpha: 1),
                type: UIColor(red: 0.39, green: 0.80, blue: 0.88, alpha: 1),
                tag: UIColor(red: 0.95, green: 0.46, blue: 0.48, alpha: 1)
                )
            }
            return palette
        }

        if isDark {
            return EditorPalette(
                background: UIColor(red: 0.115, green: 0.12, blue: 0.135, alpha: 1),
                foreground: UIColor(red: 0.89, green: 0.90, blue: 0.92, alpha: 1),
                gutterBackground: UIColor(red: 0.085, green: 0.09, blue: 0.10, alpha: 1),
                gutterForeground: UIColor(red: 0.49, green: 0.52, blue: 0.57, alpha: 1),
                keyword: UIColor(red: 0.76, green: 0.51, blue: 0.96, alpha: 1),
                string: UIColor(red: 0.65, green: 0.84, blue: 0.53, alpha: 1),
                number: UIColor(red: 0.91, green: 0.64, blue: 0.40, alpha: 1),
                comment: UIColor(red: 0.42, green: 0.59, blue: 0.44, alpha: 1),
                type: UIColor(red: 0.36, green: 0.76, blue: 0.85, alpha: 1),
                tag: UIColor(red: 0.91, green: 0.43, blue: 0.46, alpha: 1)
            )
        }

        var palette = EditorPalette(
            background: .white,
            foreground: UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1),
            gutterBackground: UIColor(red: 0.955, green: 0.96, blue: 0.97, alpha: 1),
            gutterForeground: UIColor(red: 0.46, green: 0.49, blue: 0.54, alpha: 1),
            keyword: UIColor(red: 0.48, green: 0.13, blue: 0.71, alpha: 1),
            string: UIColor(red: 0.13, green: 0.47, blue: 0.16, alpha: 1),
            number: UIColor(red: 0.72, green: 0.30, blue: 0.08, alpha: 1),
            comment: UIColor(red: 0.27, green: 0.48, blue: 0.28, alpha: 1),
            type: UIColor(red: 0.03, green: 0.45, blue: 0.60, alpha: 1),
            tag: UIColor(red: 0.68, green: 0.12, blue: 0.17, alpha: 1)
        )
        if appearance == .custom {
            palette = EditorPalette(
                background: UIColor(hex: customBackgroundHex ?? "#20242B"),
                foreground: UIColor(hex: customForegroundHex ?? "#E6EDF3"),
                gutterBackground: UIColor(hex: customBackgroundHex ?? "#20242B").withAlphaComponent(0.78),
                gutterForeground: UIColor(hex: customForegroundHex ?? "#E6EDF3").withAlphaComponent(0.62),
                keyword: palette.keyword, string: palette.string, number: palette.number, comment: palette.comment, type: palette.type, tag: palette.tag
            )
        }
        return palette
    }
}

private extension UIColor {
    convenience init(hex: String) {
        let value = hex.replacingOccurrences(of: "#", with: "")
        var number: UInt64 = 0
        Scanner(string: value).scanHexInt64(&number)
        self.init(red: CGFloat((number >> 16) & 0xFF) / 255, green: CGFloat((number >> 8) & 0xFF) / 255, blue: CGFloat(number & 0xFF) / 255, alpha: 1)
    }
}

enum SyntaxHighlighter {
    /// JSON files up to roughly 2 MB receive full lexical colouring. This is
    /// large enough for the common 劳动信息表.json document while avoiding a
    /// regex pass over arbitrarily huge files.
    static let jsonHighlightUTF16Limit = 2_000_000

    static func apply(
        to textView: UITextView,
        language: SyntaxLanguage,
        font: UIFont,
        palette: EditorPalette
    ) {
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else {
            textView.typingAttributes = [
                .font: font,
                .foregroundColor: palette.foreground
            ]
            return
        }

        storage.beginEditing()
        storage.setAttributes([
            .font: font,
            .foregroundColor: palette.foreground
        ], range: fullRange)

        // JSON gets an explicit higher limit so keys, strings and values stay
        // distinguishable in normal large documents. Other languages keep the
        // conservative limit to preserve large-file open responsiveness.
        let tier = LargeFilePolicy.tier(byteCount: 0, utf16Length: fullRange.length)
        let canHighlight = !LargeFilePolicy.disablesSyntaxHighlight(tier, language: language)
            && (fullRange.length <= LargeFilePolicy.largeUTF16Threshold
                || ((language == .json || language == .jsonc)
                    && LargeFilePolicy.allowsJSONHighlight(utf16Length: fullRange.length)))
        if canHighlight {
            highlightPatterns(
                language: language,
                in: storage.string,
                storage: storage,
                palette: palette
            )
        }
        storage.endEditing()

        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.foreground
        ]
    }

    /// Highlights the matching JSON/object delimiter when the caret is on a
    /// brace (or immediately after one). This follows the familiar
    /// Notepad++ brace-matching behavior and is deliberately lexical so braces
    /// inside strings and comments are ignored.
    @discardableResult
    static func highlightMatchingBrackets(
        in textView: UITextView,
        selection: NSRange,
        palette: EditorPalette,
        clearing previousRanges: [NSRange] = []
    ) -> [NSRange] {
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return [] }
        for range in previousRanges {
            let safe = NSIntersectionRange(range, fullRange)
            if safe.length > 0 {
                storage.removeAttribute(.backgroundColor, range: safe)
                storage.removeAttribute(.underlineStyle, range: safe)
            }
        }

        let text = storage.string as NSString
        let opening: [unichar: unichar] = [123: 125, 91: 93, 40: 41]
        let closing: [unichar: unichar] = [125: 123, 93: 91, 41: 40]
        // A tap can leave the insertion point immediately before *or* after
        // the delimiter depending on which side of the glyph was hit. Try
        // both adjacent UTF-16 positions, matching Notepad++'s forgiving
        // brace-caret behaviour instead of requiring an exact selection.
        var candidate: Int?
        let nearby = [selection.location, selection.location - 1]
        for position in nearby where position >= 0 && position < text.length {
            let value = text.character(at: position)
            if opening[value] != nil || closing[value] != nil {
                candidate = position
                break
            }
        }
        guard let candidate else { return [] }

        var stack: [(character: unichar, location: Int)] = []
        var matchLocation: Int?
        var index = 0
        var inString = false
        var escaped = false
        while index < text.length {
            let character = text.character(at: index)
            if inString {
                if escaped { escaped = false }
                else if character == 92 { escaped = true }
                else if character == 34 { inString = false }
                index += 1
                continue
            }
            if character == 34 { inString = true; index += 1; continue }
            if character == 47, index + 1 < text.length {
                let next = text.character(at: index + 1)
                if next == 47 {
                    index += 2
                    while index < text.length, text.character(at: index) != 10 { index += 1 }
                    continue
                }
                if next == 42 {
                    index += 2
                    while index + 1 < text.length {
                        if text.character(at: index) == 42, text.character(at: index + 1) == 47 {
                            index += 2
                            break
                        }
                        index += 1
                    }
                    continue
                }
            }
            if opening[character] != nil {
                stack.append((character, index))
            } else if let expectedOpening = closing[character] {
                if let last = stack.last, last.character == expectedOpening {
                    let pair = (last.location, index)
                    stack.removeLast()
                    if candidate == pair.0 { matchLocation = pair.1; break }
                    if candidate == pair.1 { matchLocation = pair.0; break }
                }
            }
            index += 1
        }
        guard let matchLocation else { return [] }
        let highlight = palette.type.withAlphaComponent(0.24)
        for location in [candidate, matchLocation] {
            storage.addAttributes([
                .backgroundColor: highlight,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: NSRange(location: location, length: 1))
        }
        return [NSRange(location: candidate, length: 1), NSRange(location: matchLocation, length: 1)]
    }

    private static func highlightPatterns(
        language: SyntaxLanguage,
        in text: String,
        storage: NSTextStorage,
        palette: EditorPalette
    ) {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        if !language.keywords.isEmpty {
            let escaped = language.keywords.map(NSRegularExpression.escapedPattern).joined(separator: "|")
            apply(#"\b(?:\#(escaped))\b"#, color: palette.keyword, to: storage, in: fullRange,
                  options: language == .sql ? .caseInsensitive : [])
        }

        apply(#"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b"#, color: palette.number, to: storage, in: fullRange)

        switch language {
        case .html, .xml:
            apply(#"</?[A-Za-z][^>]*>"#, color: palette.tag, to: storage, in: fullRange)
            apply(#""[^"]*"|'[^']*'"#, color: palette.string, to: storage, in: fullRange)
            apply(#"<!--[\s\S]*?-->"#, color: palette.comment, to: storage, in: fullRange)
        case .css:
            apply(#"[.#]?[A-Za-z_-][A-Za-z0-9_-]*(?=\s*\{)"#, color: palette.tag, to: storage, in: fullRange)
            apply(#""[^"]*"|'[^']*'"#, color: palette.string, to: storage, in: fullRange)
            apply(#"/\*[\s\S]*?\*/"#, color: palette.comment, to: storage, in: fullRange)
        case .markdown:
            apply(#"(?m)^#{1,6}\s.*$"#, color: palette.keyword, to: storage, in: fullRange)
            apply(#"`{1,3}[^`]+`{1,3}"#, color: palette.string, to: storage, in: fullRange)
            apply(#"\*\*[^*]+\*\*|__[^_]+__"#, color: palette.type, to: storage, in: fullRange)
            apply(#"(?m)^>\s.*$"#, color: palette.comment, to: storage, in: fullRange)
        case .json, .jsonc:
            apply(#""(?:\\.|[^"\\])*""#, color: palette.string, to: storage, in: fullRange)
            // Re-apply keys after strings so keys retain their distinct color.
            apply(#""(?:\\.|[^"\\])*"(?=\s*:)"#, color: palette.tag, to: storage, in: fullRange)
            // JSON literals are semantically distinct from strings and
            // numbers; keep them visually distinct in large payloads too.
            apply(#"\b(?:true|false|null)\b"#, color: palette.keyword, to: storage, in: fullRange)
            apply(#"//.*?$|/\*[\s\S]*?\*/"#, color: palette.comment, to: storage, in: fullRange, options: .anchorsMatchLines)
        case .toml:
            apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: palette.string, to: storage, in: fullRange)
            apply(#"(?m)#.*$"#, color: palette.comment, to: storage, in: fullRange)
        case .python, .shell, .yaml:
            apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: palette.string, to: storage, in: fullRange)
            apply(#"(?m)#.*$"#, color: palette.comment, to: storage, in: fullRange)
        case .plainText:
            // Even ordinary text often contains configuration snippets and
            // comment markers. Keep these visually distinct without treating
            // the document as a programming language.
            apply(#"(?m)#.*$"#, color: palette.comment, to: storage, in: fullRange)
            apply(#"//.*?$|/\*[\s\S]*?\*/"#, color: palette.comment, to: storage, in: fullRange, options: .anchorsMatchLines)
        default:
            apply(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, color: palette.string, to: storage, in: fullRange)
            apply(#"//.*?$|/\*[\s\S]*?\*/"#, color: palette.comment, to: storage, in: fullRange, options: .anchorsMatchLines)
        }
    }

    private static func apply(
        _ pattern: String,
        color: UIColor,
        to storage: NSTextStorage,
        in range: NSRange,
        options: NSRegularExpression.Options = []
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        expression.enumerateMatches(in: storage.string, range: range) { result, _, _ in
            guard let result else { return }
            storage.addAttribute(.foregroundColor, value: color, range: result.range)
        }
    }
}
