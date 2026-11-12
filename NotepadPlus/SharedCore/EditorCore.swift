import Foundation

public enum SyntaxLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case plainText
    case swift
    case objectiveC
    case c
    case cpp
    case python
    case javascript
    case typescript
    case html
    case xml
    case css
    case json
    case jsonc
    case toml
    case markdown
    case shell
    case sql
    case yaml

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plainText: "Normal text"
        case .swift: "Swift"
        case .objectiveC: "Objective-C"
        case .c: "C"
        case .cpp: "C++"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .html: "HTML"
        case .xml: "XML"
        case .css: "CSS"
        case .json: "JSON"
        case .jsonc: "JSONC"
        case .toml: "TOML"
        case .markdown: "Markdown"
        case .shell: "Shell"
        case .sql: "SQL"
        case .yaml: "YAML"
        }
    }

    public var keywords: [String] {
        switch self {
        case .swift:
            ["actor", "any", "as", "associatedtype", "async", "await", "break", "case",
             "catch", "class", "continue", "default", "defer", "deinit", "do", "else",
             "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func",
             "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
             "nil", "nonisolated", "open", "operator", "private", "protocol", "public",
             "repeat", "rethrows", "return", "self", "some", "static", "struct", "subscript",
             "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while"]
        case .objectiveC, .c, .cpp:
            ["alignas", "auto", "bool", "break", "case", "catch", "char", "class", "const",
             "constexpr", "continue", "default", "delete", "do", "double", "else", "enum",
             "explicit", "extern", "false", "float", "for", "friend", "if", "inline", "int",
             "long", "namespace", "new", "nullptr", "operator", "private", "protected",
             "public", "return", "short", "signed", "sizeof", "static", "struct", "switch",
             "template", "this", "throw", "true", "try", "typedef", "union", "unsigned",
             "using", "virtual", "void", "volatile", "while"]
        case .python:
            ["and", "as", "assert", "async", "await", "break", "case", "class", "continue",
             "def", "del", "elif", "else", "except", "False", "finally", "for", "from",
             "global", "if", "import", "in", "is", "lambda", "match", "None", "nonlocal",
             "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"]
        case .javascript, .typescript:
            ["async", "await", "break", "case", "catch", "class", "const", "continue",
             "debugger", "default", "delete", "do", "else", "enum", "export", "extends",
             "false", "finally", "for", "from", "function", "if", "implements", "import",
             "in", "instanceof", "interface", "let", "new", "null", "of", "package",
             "private", "protected", "public", "return", "static", "super", "switch",
             "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"]
        case .sql:
            ["ADD", "ALTER", "AND", "AS", "ASC", "BEGIN", "BETWEEN", "BY", "CASE",
             "CREATE", "DATABASE", "DELETE", "DESC", "DISTINCT", "DROP", "ELSE", "END",
             "EXISTS", "FROM", "FULL", "GROUP", "HAVING", "IN", "INDEX", "INNER",
             "INSERT", "INTO", "IS", "JOIN", "LEFT", "LIKE", "LIMIT", "NOT", "NULL",
             "ON", "OR", "ORDER", "OUTER", "RIGHT", "SELECT", "SET", "TABLE", "THEN",
             "UNION", "UNIQUE", "UPDATE", "VALUES", "VIEW", "WHEN", "WHERE", "WITH"]
        default:
            []
        }
    }

    public static func detect(filename: String) -> SyntaxLanguage {
        let name = filename.lowercased()
        if name == "dockerfile" || name == "makefile" { return .shell }
        let ext = (name as NSString).pathExtension
        switch ext {
        case "swift": return .swift
        case "m", "mm", "h": return .objectiveC
        case "c": return .c
        case "cc", "cpp", "cxx", "hpp", "hxx": return .cpp
        case "py", "pyw": return .python
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx": return .typescript
        case "html", "htm": return .html
        case "xml", "svg", "plist": return .xml
        case "css", "scss", "sass", "less": return .css
        case "json": return .json
        case "jsonc": return .jsonc
        case "toml": return .toml
        case "md", "markdown": return .markdown
        case "sh", "bash", "zsh", "fish": return .shell
        case "sql": return .sql
        case "yaml", "yml": return .yaml
        default: return .plainText
        }
    }
}

public enum SearchMode: String, CaseIterable, Identifiable, Sendable {
    case normal, extended, regularExpression
    public var id: String { rawValue }
}

public struct SearchOptions: Equatable, Sendable {
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var mode: SearchMode
    public var regularExpression: Bool {
        get { mode == .regularExpression }
        set {
            if newValue { mode = .regularExpression }
            else if mode == .regularExpression { mode = .normal }
        }
    }
    /// Matches Notepad++'s “. matches newline” regular-expression option.
    /// It is intentionally ignored for literal searches.
    public var dotMatchesNewline: Bool

    public init(
        caseSensitive: Bool = false,
        wholeWord: Bool = false,
        regularExpression: Bool = false,
        dotMatchesNewline: Bool = false,
        mode: SearchMode = .normal
    ) {
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.mode = regularExpression ? .regularExpression : mode
        self.dotMatchesNewline = dotMatchesNewline
    }
}

public enum SearchDirection: Sendable {
    case forward
    case backward
}

public enum SearchError: LocalizedError, Equatable {
    case invalidRegularExpression(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRegularExpression(let reason):
            "Invalid regular expression: \(reason)"
        }
    }
}

public enum SearchEngine {
    private static func expression(query: String, options: SearchOptions) throws -> NSRegularExpression {
        let literal = options.mode == .extended ? decodeExtended(query) : query
        var pattern = options.regularExpression ? query : NSRegularExpression.escapedPattern(for: literal)
        // Notepad++ disables "whole word" in regex mode; grouping must not
        // change capture numbering or the meaning of a user's expression.
        if options.wholeWord && !options.regularExpression {
            pattern = #"(?<![\p{L}\p{N}_])(?:\#(pattern))(?![\p{L}\p{N}_])"#
        }
        var flags: NSRegularExpression.Options = []
        if !options.caseSensitive { flags.insert(.caseInsensitive) }
        if options.regularExpression {
            flags.insert(.anchorsMatchLines)
            if options.dotMatchesNewline { flags.insert(.dotMatchesLineSeparators) }
        }
        do {
            return try NSRegularExpression(pattern: pattern, options: flags)
        } catch {
            throw SearchError.invalidRegularExpression(error.localizedDescription)
        }
    }

    private static func boundedRange(_ range: NSRange?, length: Int) -> NSRange {
        guard let range else { return NSRange(location: 0, length: length) }
        guard range.location != NSNotFound, range.location >= 0, range.location <= length else {
            return NSRange(location: length, length: 0)
        }
        return NSRange(location: range.location, length: min(max(0, range.length), length - range.location))
    }

    private static func results(
        _ expression: NSRegularExpression, in text: String, range: NSRange?
    ) -> [NSTextCheckingResult] {
        if let range, (range.location == NSNotFound || range.location < 0 || range.location > (text as NSString).length || range.length < 0) {
            return []
        }
        return expression.matches(
            in: text,
            options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: boundedRange(range, length: (text as NSString).length)
        )
    }

    public static func matches(
        in text: String,
        query: String,
        options: SearchOptions,
        in searchRange: NSRange? = nil
    ) throws -> [NSRange] {
        guard !query.isEmpty else { return [] }
        return results(try expression(query: query, options: options), in: text, range: searchRange).map(\.range)
    }

    public static func nextMatch(
        in text: String,
        query: String,
        after location: Int,
        options: SearchOptions,
        direction: SearchDirection = .forward,
        wrap: Bool = true
    ) throws -> NSRange? {
        let all = try matches(in: text, query: query, options: options)
        guard !all.isEmpty else { return nil }
        switch direction {
        case .forward:
            return all.first(where: { $0.location >= location }) ?? (wrap ? all[0] : nil)
        case .backward:
            return all.last(where: { $0.location < location }) ?? (wrap ? all.last : nil)
        }
    }

    public static func replaceAll(
        in text: String,
        query: String,
        replacement: String,
        options: SearchOptions,
        in searchRange: NSRange? = nil
    ) throws -> (text: String, count: Int) {
        guard !query.isEmpty else { return (text, 0) }
        let expression = try expression(query: query, options: options)
        let all = results(expression, in: text, range: searchRange)
        guard !all.isEmpty else { return (text, 0) }
        let mutable = NSMutableString(string: text)
        for match in all.reversed() {
            mutable.replaceCharacters(
                in: match.range,
                with: replacementText(replacement, match: match, text: text, options: options)
            )
        }
        return (mutable as String, all.count)
    }

    public static func replaceMatch(
        in text: String,
        range: NSRange,
        query: String,
        replacement: String,
        options: SearchOptions,
        in searchRange: NSRange? = nil
    ) throws -> (text: String, replacementRange: NSRange) {
        guard !query.isEmpty else { return (text, range) }
        let expression = try expression(query: query, options: options)
        // Match against the document, not an isolated substring: lookarounds,
        // anchors, and whole-word boundaries must retain their real context.
        guard let match = results(expression, in: text, range: searchRange).first(where: { $0.range == range }) else {
            return (text, range)
        }
        let value = replacementText(replacement, match: match, text: text, options: options)
        let result = (text as NSString).replacingCharacters(in: range, with: value)
        return (
            result,
            NSRange(location: range.location, length: (value as NSString).length)
        )
    }

    /// Extended mode follows Searching::convertExtendedToString in Notepad++:
    /// unknown or incomplete escape sequences remain literal.
    public static func decodeExtended(_ text: String) -> String {
        let characters = Array(text)
        var result: [UInt16] = []
        var index = 0
        while index < characters.count {
            guard characters[index] == "\\", index + 1 < characters.count else {
                result.append(contentsOf: String(characters[index]).utf16); index += 1; continue
            }
            let next = characters[index + 1]
            let escapes: [Character: String] = ["n": "\n", "r": "\r", "t": "\t", "0": "\0", "\\": "\\"]
            if let value = escapes[next] {
                result.append(contentsOf: value.utf16); index += 2; continue
            }
            let formats: [Character: (Int, Int)] = ["b": (8, 2), "o": (3, 8), "d": (3, 10), "x": (2, 16), "u": (4, 16)]
            if let (count, radix) = formats[next], index + 2 + count <= characters.count {
                let digits = String(characters[(index + 2)..<(index + 2 + count)])
                if let value = UInt16(digits, radix: radix) {
                    result.append(value); index += 2 + count; continue
                }
            }
            result.append(contentsOf: "\\".utf16)
            result.append(contentsOf: String(next).utf16)
            index += 2
        }
        return String(decoding: result, as: UTF16.self)
    }

    public static func literalReplacement(_ text: String, options: SearchOptions) -> String {
        guard options.mode != .normal else { return text }
        var value = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        if options.regularExpression { value = value.replacingOccurrences(of: "$", with: "\\$") }
        else { value = value.replacingOccurrences(of: "\0", with: "\\0") }
        return value
    }

    private static func replacementText(
        _ template: String, match: NSTextCheckingResult, text: String, options: SearchOptions
    ) -> String {
        if options.mode == .normal { return template }
        if options.mode == .extended { return decodeExtended(template) }
        let source = text as NSString
        func capture(_ number: Int) -> String {
            guard number >= 0, number < match.numberOfRanges else { return "" }
            let range = match.range(at: number)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
        let chars = Array(template)
        var output = ""
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\\", index + 1 < chars.count {
                let next = chars[index + 1]
                if let number = next.wholeNumberValue, next.isASCII {
                    output += capture(number)
                } else {
                    let escapes: [Character: String] = ["n": "\n", "r": "\r", "t": "\t", "a": "\u{7}", "f": "\u{c}", "e": "\u{1b}", "v": "\u{b}"]
                    output += escapes[next] ?? String(next)
                }
                index += 2; continue
            }
            if char == "$", index + 1 < chars.count {
                let next = chars[index + 1]
                if next == "$" { output += "$"; index += 2; continue }
                if next == "&" { output += capture(0); index += 2; continue }
                if next.isASCII, let number = next.wholeNumberValue {
                    output += capture(number); index += 2; continue
                }
                let named = next == "+" && index + 2 < chars.count && chars[index + 2] == "{"
                let start = index + (named ? 3 : 2)
                if (next == "{" || named), let end = chars[start...].firstIndex(of: "}") {
                    let key = String(chars[start..<end])
                    if named {
                        let range = match.range(withName: key)
                        if range.location != NSNotFound { output += source.substring(with: range) }
                    } else if let number = Int(key) {
                        output += capture(number)
                    } else {
                        output += String(chars[index...end])
                    }
                    index = end + 1; continue
                }
            }
            output.append(char); index += 1
        }
        return output
    }
}

public enum TextTransformation: String, CaseIterable, Identifiable, Sendable {
    case uppercase
    case lowercase
    case capitalize
    case trimTrailingWhitespace
    case sortLinesAscending
    case sortLinesDescending
    case removeDuplicateLines

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        case .capitalize: "Capitalize Words"
        case .trimTrailingWhitespace: "Trim Trailing Space"
        case .sortLinesAscending: "Sort Lines A → Z"
        case .sortLinesDescending: "Sort Lines Z → A"
        case .removeDuplicateLines: "Remove Duplicate Lines"
        }
    }

    public func apply(to text: String) -> String {
        switch self {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .capitalize:
            return text.capitalized
        case .trimTrailingWhitespace:
            return text
                .components(separatedBy: "\n")
                .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
                .joined(separator: "\n")
        case .sortLinesAscending:
            return text.components(separatedBy: "\n").sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }.joined(separator: "\n")
        case .sortLinesDescending:
            return text.components(separatedBy: "\n").sorted {
                $0.localizedStandardCompare($1) == .orderedDescending
            }.joined(separator: "\n")
        case .removeDuplicateLines:
            var seen = Set<String>()
            return text.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
        }
    }
}

/// JSON 的格式化结果。`wasRepaired` 为 `true` 表示格式化前已自动修复了常见的小语法问题。
public struct JSONFormattingResult: Equatable, Sendable {
    public let text: String
    public let wasRepaired: Bool

    public init(text: String, wasRepaired: Bool) {
        self.text = text
        self.wasRepaired = wasRepaired
    }
}

public enum JSONFormattingError: LocalizedError, Equatable, Sendable {
    case emptyInput
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            "没有可格式化的 JSON 内容。"
        case .invalidJSON:
            "无法识别为 JSON。已尝试修复注释、未加引号的键名和多余逗号；请检查括号、字符串和分隔符。"
        }
    }
}

/// 面向编辑器的 JSON 美化工具。
///
/// 除标准 JSON 外，会安全处理常见的 JSONC/手写 JSON 问题：行/块注释、对象键名漏引号、
/// 尾逗号、单引号字符串和开头 BOM。修复后仍必须能通过系统 JSON 解析器验证，才会写回编辑器。
public enum JSONFormatter {
    public static func format(_ source: String) throws -> JSONFormattingResult {
        let candidate = source
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .droppingByteOrderMark()
        guard !candidate.isEmpty else { throw JSONFormattingError.emptyInput }

        if let formatted = prettyPrinted(candidate) {
            return JSONFormattingResult(text: formatted, wasRepaired: false)
        }

        let repaired = JSONRepairer.repair(candidate)
        guard repaired != candidate, let formatted = prettyPrinted(repaired) else {
            throw JSONFormattingError.invalidJSON
        }
        return JSONFormattingResult(text: formatted, wasRepaired: true)
    }

    private static func prettyPrinted(_ source: String) -> String? {
        guard let data = source.data(using: .utf8) else { return nil }
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            let output = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
            )
            return String(data: output, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

/// Multiline object/array regions that can be collapsed in the editor.
public enum JSONFolding {
    /// Returns a map from the opening delimiter's 1-based line number to the
    /// UTF-16 range of lines after that delimiter through its matching close.
    /// The opening line is intentionally kept visible (so its +/- control and
    /// opening brace remain available); the closing line is part of the hidden
    /// range, matching Scintilla/Notepad++'s fold contraction behavior.
    public static func regions(in source: String) -> [Int: NSRange] {
        let text = source as NSString
        guard text.length > 0 else { return [:] }
        // Track line starts during the lexical scan. Calling
        // TextStatistics.lineAndColumn for every delimiter repeatedly creates
        // prefixes and turns deeply nested/large JSON into an avoidable O(n²)
        // operation.
        var lineStarts = [0]
        lineStarts.reserveCapacity(max(1, text.length / 40))
        var stack: [(character: unichar, location: Int, line: Int)] = []
        // Defer turning pairs into ranges until the lexical scan has ended.
        // While visiting a closing delimiter, the start of the *next* line
        // has not been recorded yet. Building the range at that point makes
        // every container whose close is not followed by a newline extend to
        // EOF (for example, line 28's short `cascader` array in large JSON).
        var completed: [(openLine: Int, closeLine: Int)] = []
        var index = 0
        var line = 1
        var inString = false
        var escaped = false
        while index < text.length {
            let character = text.character(at: index)
            if inString {
                if escaped { escaped = false }
                else if character == 92 { escaped = true }
                else if character == 34 { inString = false }
                if character == 10 {
                    line += 1
                    lineStarts.append(index + 1)
                }
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
                        if text.character(at: index) == 10 {
                            line += 1
                            lineStarts.append(index + 1)
                        }
                        index += 1
                    }
                    continue
                }
            }
            let isOpening = character == 123 || character == 91
            if isOpening {
                stack.append((character, index, line))
            } else if (character == 125 || character == 93), let opening = stack.last,
                      (opening.character == 123 && character == 125) || (opening.character == 91 && character == 93) {
                stack.removeLast()
                let openLine = opening.line
                let closeLine = line
                if closeLine > openLine + 0 {
                    completed.append((openLine: openLine, closeLine: closeLine))
                }
            }
            if character == 10 {
                line += 1
                lineStarts.append(index + 1)
            }
            index += 1
        }
        var result: [Int: NSRange] = [:]
        result.reserveCapacity(completed.count)
        for pair in completed {
            guard pair.openLine < lineStarts.count else { continue }
            let start = lineStarts[pair.openLine]
            // After the scan, lineStarts contains the start of the line after
            // the matching close whenever that line exists. This includes the
            // complete closing line without hiding unrelated trailing text.
            let end = pair.closeLine < lineStarts.count
                ? lineStarts[pair.closeLine]
                : text.length
            if end > start {
                result[pair.openLine] = NSRange(location: start, length: end - start)
            }
        }
        return result
    }
}

/// Brace-based fold regions for C-like languages. Only `{`/`}` pairs create
/// fold points — parentheses and brackets are too noisy for an outline fold.
public enum BraceFolding {
    public static func regions(in source: String) -> [Int: NSRange] {
        let text = source as NSString
        guard text.length > 0 else { return [:] }
        var lineStarts = [0]
        lineStarts.reserveCapacity(max(1, text.length / 40))
        var stack: [(location: Int, line: Int)] = []
        var completed: [(openLine: Int, closeLine: Int)] = []
        var index = 0
        var line = 1
        var inString = false
        var stringDelimiter: unichar = 0
        var escaped = false
        var inLineComment = false
        var inBlockComment = false

        while index < text.length {
            let character = text.character(at: index)

            if inLineComment {
                if character == 10 {
                    inLineComment = false
                    line += 1
                    lineStarts.append(index + 1)
                }
                index += 1
                continue
            }
            if inBlockComment {
                if character == 42, index + 1 < text.length, text.character(at: index + 1) == 47 {
                    index += 2
                    inBlockComment = false
                    continue
                }
                if character == 10 {
                    line += 1
                    lineStarts.append(index + 1)
                }
                index += 1
                continue
            }
            if inString {
                if escaped {
                    escaped = false
                } else if character == 92 {
                    escaped = true
                } else if character == stringDelimiter {
                    inString = false
                }
                if character == 10 {
                    line += 1
                    lineStarts.append(index + 1)
                }
                index += 1
                continue
            }

            if character == 34 || character == 39 { // " or '
                inString = true
                stringDelimiter = character
                index += 1
                continue
            }
            if character == 47, index + 1 < text.length {
                let next = text.character(at: index + 1)
                if next == 47 {
                    inLineComment = true
                    index += 2
                    continue
                }
                if next == 42 {
                    inBlockComment = true
                    index += 2
                    continue
                }
            }

            if character == 123 {
                stack.append((index, line))
            } else if character == 125, let opening = stack.popLast() {
                if line > opening.line {
                    completed.append((openLine: opening.line, closeLine: line))
                }
            }

            if character == 10 {
                line += 1
                lineStarts.append(index + 1)
            }
            index += 1
        }

        var result: [Int: NSRange] = [:]
        result.reserveCapacity(completed.count)
        for pair in completed {
            guard pair.openLine < lineStarts.count else { continue }
            let start = lineStarts[pair.openLine]
            let end = pair.closeLine < lineStarts.count
                ? lineStarts[pair.closeLine]
                : text.length
            if end > start {
                result[pair.openLine] = NSRange(location: start, length: end - start)
            }
        }
        return result
    }

    public static func supports(_ language: SyntaxLanguage) -> Bool {
        switch language {
        case .swift, .objectiveC, .c, .cpp, .javascript, .typescript, .css:
            return true
        default:
            return false
        }
    }
}

/// Locates the smallest JSON member/array item around the caret so editors can
/// remove a value without forcing the user to manually select punctuation.
/// This is intentionally a lexical helper: it stays fast for large documents,
/// tolerates JSONC comments, and does not deserialize the whole file.
public enum JSONValueEditing {
    private enum TokenKind: Equatable {
        case string
        case atom
        case opening(Character)
        case closing(Character)
        case colon
        case comma
    }

    private struct Token {
        let kind: TokenKind
        let range: NSRange
    }

    private struct Pair {
        let open: Int
        let close: Int
        let kind: Character
    }

    /// Returns the range to remove for the JSON value/member at `selection`.
    /// Object members include their key and comma; array entries include the
    /// entry and comma. The root value itself is returned for a root document.
    public static func deletionRange(in source: String, selection: NSRange) -> NSRange? {
        let text = source as NSString
        guard text.length > 0 else { return nil }
        let tokens = tokenize(source)
        guard !tokens.isEmpty else { return nil }
        let safeLocation = min(max(selection.location, 0), text.length)
        let safeEnd = min(max(NSMaxRange(selection), safeLocation), text.length)

        let candidateIndex = tokens.firstIndex { token in
            let start = token.range.location
            let end = NSMaxRange(token.range)
            return (selection.length > 0 && start < safeEnd && end > safeLocation)
                || (selection.length == 0 && safeLocation >= start && safeLocation <= end)
        }
        guard let index = candidateIndex else { return nil }

        var valueIndex = index
        if case .string = tokens[valueIndex].kind,
           valueIndex + 1 < tokens.count,
           tokens[valueIndex + 1].kind == .colon {
            valueIndex += 2
        } else if tokens[valueIndex].kind == .colon, valueIndex + 1 < tokens.count {
            valueIndex += 1
        }
        guard valueIndex < tokens.count else { return nil }
        let pairs = matchingPairs(tokens)
        let valueToken = tokens[valueIndex]
        guard isValueToken(valueToken.kind) else { return nil }
        let valueRange: NSRange
        var valueEndIndex = valueIndex
        if case .opening = valueToken.kind,
           let pair = pairs.first(where: { $0.open == valueToken.range.location }) {
            valueRange = NSRange(location: pair.open, length: pair.close - pair.open)
            valueEndIndex = tokens.firstIndex { $0.range.location == pair.close - 1 } ?? valueIndex
        } else {
            valueRange = valueToken.range
        }
        let containing = pairs
            .filter { $0.open < valueRange.location && NSMaxRange(valueRange) <= $0.close }
            .sorted { ($0.close - $0.open) < ($1.close - $1.open) }
            .first

        guard let container = containing else { return valueRange }
        let containerIsObject = container.kind == "{"
        var memberStart = valueIndex
        if containerIsObject {
            guard valueIndex >= 2,
                  case .colon = tokens[valueIndex - 1].kind,
                  case .string = tokens[valueIndex - 2].kind else { return valueRange }
            memberStart = valueIndex - 2
        }

        let memberEnd = valueEndIndex
        let after = memberEnd + 1
        if after < tokens.count, tokens[after].kind == .comma {
            return NSRange(
                location: tokens[memberStart].range.location,
                length: NSMaxRange(tokens[after].range) - tokens[memberStart].range.location
            )
        }
        if memberStart > 0,
           tokens[memberStart - 1].kind == .comma,
           tokens[memberStart - 1].range.location > container.open {
            return NSRange(
                location: tokens[memberStart - 1].range.location,
                length: NSMaxRange(tokens[memberEnd].range) - tokens[memberStart - 1].range.location
            )
        }
        return NSRange(
            location: tokens[memberStart].range.location,
            length: NSMaxRange(tokens[memberEnd].range) - tokens[memberStart].range.location
        )
    }

    private static func isValueToken(_ kind: TokenKind) -> Bool {
        switch kind {
        case .string, .atom, .opening: return true
        default: return false
        }
    }

    private static func matchingPairs(_ tokens: [Token]) -> [Pair] {
        var stack: [(index: Int, kind: Character)] = []
        var pairs: [Pair] = []
        for (index, token) in tokens.enumerated() {
            switch token.kind {
            case .opening(let kind): stack.append((index, kind))
            case .closing(let kind):
                guard let last = stack.last,
                      (last.kind == "{" && kind == "}") || (last.kind == "[" && kind == "]")
                else { continue }
                stack.removeLast()
                pairs.append(Pair(
                    open: tokens[last.index].range.location,
                    close: NSMaxRange(token.range),
                    kind: last.kind
                ))
            default: break
            }
        }
        return pairs
    }

    private static func tokenize(_ source: String) -> [Token] {
        let text = source as NSString
        var result: [Token] = []
        result.reserveCapacity(min(text.length / 4, 200_000))
        var index = 0
        while index < text.length {
            let character = text.character(at: index)
            if character == 32 || character == 9 || character == 10 || character == 13 {
                index += 1; continue
            }
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
                            index += 2; break
                        }
                        index += 1
                    }
                    continue
                }
            }
            let start = index
            switch character {
            case 34:
                index += 1
                var escaped = false
                while index < text.length {
                    let value = text.character(at: index)
                    index += 1
                    if escaped { escaped = false }
                    else if value == 92 { escaped = true }
                    else if value == 34 { break }
                }
                result.append(Token(kind: .string, range: NSRange(location: start, length: index - start)))
            case 123: index += 1; result.append(Token(kind: .opening("{"), range: NSRange(location: start, length: 1)))
            case 91: index += 1; result.append(Token(kind: .opening("["), range: NSRange(location: start, length: 1)))
            case 125: index += 1; result.append(Token(kind: .closing("}"), range: NSRange(location: start, length: 1)))
            case 93: index += 1; result.append(Token(kind: .closing("]"), range: NSRange(location: start, length: 1)))
            case 58: index += 1; result.append(Token(kind: .colon, range: NSRange(location: start, length: 1)))
            case 44: index += 1; result.append(Token(kind: .comma, range: NSRange(location: start, length: 1)))
            default:
                index += 1
                while index < text.length {
                    let value = text.character(at: index)
                    if value == 32 || value == 9 || value == 10 || value == 13
                        || [34, 44, 58, 91, 93, 123, 125].contains(Int(value)) { break }
                    index += 1
                }
                result.append(Token(kind: .atom, range: NSRange(location: start, length: index - start)))
            }
        }
        return result
    }
}

private enum JSONRepairer {
    private enum Container {
        case object(expectingKey: Bool)
        case array
    }

    static func repair(_ source: String) -> String {
        let commentsRemoved = removeCommentsAndNormalizeSingleQuotedStrings(source)
        let quotedKeys = quoteBareObjectKeys(in: commentsRemoved)
        return removeTrailingCommas(in: quotedKeys)
    }

    /// 移除 JSONC 注释，但保留字符串中的 `https://`、`/* text */` 等原始内容。
    /// 单引号字符串会转换成有效 JSON 字符串，作为保守的便利修复。
    private static func removeCommentsAndNormalizeSingleQuotedStrings(_ source: String) -> String {
        let characters = Array(source)
        var index = 0
        var output = ""

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                appendDoubleQuotedString(from: characters, index: &index, to: &output)
            } else if character == "'" {
                appendSingleQuotedStringAsJSON(from: characters, index: &index, to: &output)
            } else if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                index += 2
                while index < characters.count, characters[index] != "\n", characters[index] != "\r" {
                    index += 1
                }
            } else if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                index += 2
                while index < characters.count {
                    if index + 1 < characters.count, characters[index] == "*", characters[index + 1] == "/" {
                        index += 2
                        break
                    }
                    if characters[index] == "\n" || characters[index] == "\r" {
                        output.append(characters[index])
                    }
                    index += 1
                }
            } else {
                output.append(character)
                index += 1
            }
        }
        return output
    }

    private static func quoteBareObjectKeys(in source: String) -> String {
        let characters = Array(source)
        var containers: [Container] = []
        var index = 0
        var output = ""

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                appendDoubleQuotedString(from: characters, index: &index, to: &output)
                markCurrentObjectHasKey(&containers)
                continue
            }

            switch character {
            case "{":
                output.append(character)
                containers.append(.object(expectingKey: true))
                index += 1
            case "[":
                output.append(character)
                containers.append(.array)
                index += 1
            case "}", "]":
                output.append(character)
                if !containers.isEmpty { containers.removeLast() }
                index += 1
            case ",":
                output.append(character)
                markCurrentObjectExpectingKey(&containers)
                index += 1
            case ":":
                output.append(character)
                markCurrentObjectHasKey(&containers)
                index += 1
            default:
                if currentObjectExpectsKey(containers), !character.isWhitespace,
                   let key = bareKey(at: index, in: characters) {
                    output.append("\"")
                    output.append(contentsOf: key.value.replacingOccurrences(of: "\"", with: "\\\""))
                    output.append("\"")
                    output.append(contentsOf: characters[key.valueEnd..<key.colonIndex])
                    index = key.colonIndex
                } else {
                    output.append(character)
                    index += 1
                }
            }
        }
        return output
    }

    /// 找到位于对象开头或逗号后的未加引号键名，例如 `group :`。
    private static func bareKey(at start: Int, in characters: [Character]) -> (value: String, valueEnd: Int, colonIndex: Int)? {
        var valueEnd = start
        while valueEnd < characters.count,
              !characters[valueEnd].isWhitespace,
              characters[valueEnd] != ":",
              characters[valueEnd] != ",",
              characters[valueEnd] != "{",
              characters[valueEnd] != "}",
              characters[valueEnd] != "[",
              characters[valueEnd] != "]" {
            valueEnd += 1
        }
        guard valueEnd > start else { return nil }

        var colonIndex = valueEnd
        while colonIndex < characters.count, characters[colonIndex].isWhitespace {
            colonIndex += 1
        }
        guard colonIndex < characters.count, characters[colonIndex] == ":" else { return nil }
        return (String(characters[start..<valueEnd]), valueEnd, colonIndex)
    }

    private static func removeTrailingCommas(in source: String) -> String {
        let characters = Array(source)
        var index = 0
        var output = ""

        while index < characters.count {
            let character = characters[index]
            if character == "\"" {
                appendDoubleQuotedString(from: characters, index: &index, to: &output)
                continue
            }
            if character == "," {
                var next = index + 1
                while next < characters.count, characters[next].isWhitespace { next += 1 }
                if next < characters.count, characters[next] == "}" || characters[next] == "]" {
                    index += 1
                    continue
                }
            }
            output.append(character)
            index += 1
        }
        return output
    }

    private static func appendDoubleQuotedString(
        from characters: [Character],
        index: inout Int,
        to output: inout String
    ) {
        output.append("\"")
        index += 1
        while index < characters.count {
            let character = characters[index]
            output.append(character)
            index += 1
            if character == "\\", index < characters.count {
                output.append(characters[index])
                index += 1
            } else if character == "\"" {
                break
            }
        }
    }

    private static func appendSingleQuotedStringAsJSON(
        from characters: [Character],
        index: inout Int,
        to output: inout String
    ) {
        output.append("\"")
        index += 1
        while index < characters.count {
            let character = characters[index]
            if character == "'" {
                output.append("\"")
                index += 1
                return
            }
            if character == "\\", index + 1 < characters.count {
                let escaped = characters[index + 1]
                if escaped == "'" {
                    output.append("'")
                } else {
                    output.append("\\")
                    output.append(escaped)
                }
                index += 2
            } else if character == "\"" {
                output.append("\\\"")
                index += 1
            } else {
                output.append(character)
                index += 1
            }
        }
        // 未闭合单引号仍然保留为无效 JSON，交由最终解析器拒绝，而不是猜测内容边界。
    }

    private static func currentObjectExpectsKey(_ containers: [Container]) -> Bool {
        guard case .object(let expectingKey)? = containers.last else { return false }
        return expectingKey
    }

    private static func markCurrentObjectExpectingKey(_ containers: inout [Container]) {
        guard case .object? = containers.last else { return }
        containers[containers.count - 1] = .object(expectingKey: true)
    }

    private static func markCurrentObjectHasKey(_ containers: inout [Container]) {
        guard case .object? = containers.last else { return }
        containers[containers.count - 1] = .object(expectingKey: false)
    }
}

private extension String {
    func droppingByteOrderMark() -> String {
        first == "\u{FEFF}" ? String(dropFirst()) : self
    }
}

public enum TextStatistics {
    public static func lineAndColumn(in text: String, utf16Location: Int) -> (line: Int, column: Int) {
        let nsText = text as NSString
        let safeLocation = min(max(utf16Location, 0), nsText.length)
        var line = 1
        var lineStart = 0
        var index = 0
        while index < safeLocation {
            if nsText.character(at: index) == 10 {
                line += 1
                lineStart = index + 1
            }
            index += 1
        }
        return (line, safeLocation - lineStart + 1)
    }

    public static func lineCount(in text: String) -> Int {
        text.isEmpty ? 1 : text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    public static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).count
    }

    public static func characterCount(in text: String) -> Int {
        text.count
    }

    public static func byteCount(in text: String) -> Int {
        text.lengthOfBytes(using: .utf8)
    }
}

/// Selection helpers used by the UIKit editor. Keeping the range calculation
/// independent from the view makes it cheap to exercise with large documents
/// and prevents a Select All implementation from accidentally walking every
/// line (which is especially costly when column mode is enabled).
public enum TextSelectionEngine {
    public static func allRange(in text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }
}

/// Per-document viewport cache. The editor view converts to/from CGPoint at
/// its UIKit boundary; this value type keeps the state logic testable without
/// requiring a UIKit test target.
///
/// `anchorLocation` is the UTF-16 index of the first visible line and
/// `anchorPixelDelta` is the sub-line pixel offset. Together they are the
/// same model Scintilla uses (`topLine` plus a pixel delta): a raw content
/// offset becomes wrong when TextKit replaces an estimated content size,
/// but the line anchor still refers to the line the user was reading.
public struct EditorScrollPosition: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let anchorLocation: Int
    public let anchorPixelDelta: Double

    public init(
        x: Double = 0,
        y: Double = 0,
        anchorLocation: Int = 0,
        anchorPixelDelta: Double = 0
    ) {
        self.x = x
        self.y = y
        self.anchorLocation = anchorLocation
        self.anchorPixelDelta = anchorPixelDelta
    }
}

/// Converts between a scroll offset and the first visible line.
/// Scintilla stores the viewport as a line index, so a later layout pass can
/// put that same line back on screen instead of clamping a stale pixel offset
/// to the top or the end of the document.
public enum ViewportAnchorMath {
    public static func capture(
        contentOffsetY: Double,
        insetTop: Double,
        lineHeight: Double,
        lineCount: Int
    ) -> (line: Int, pixelDelta: Double) {
        let height = max(lineHeight, 1)
        let count = max(lineCount, 1)
        let textY = contentOffsetY - insetTop
        var line = Int(floor(textY / height))
        if textY < 0 { line = 0 }
        line = min(max(0, line), count - 1)
        let pixelDelta = contentOffsetY - insetTop - Double(line) * height
        return (line, pixelDelta)
    }

    public static func contentOffsetY(
        line: Int,
        pixelDelta: Double,
        insetTop: Double,
        lineHeight: Double
    ) -> Double {
        let countLine = max(0, line)
        return insetTop + Double(countLine) * max(lineHeight, 1) + pixelDelta
    }
}

public final class DocumentScrollPositionStore: @unchecked Sendable {
    private var offsets: [UUID: EditorScrollPosition] = [:]

    public init() {}

    public func set(_ offset: EditorScrollPosition, for documentID: UUID) {
        offsets[documentID] = offset
    }

    public func offset(for documentID: UUID) -> EditorScrollPosition? {
        offsets[documentID]
    }

    public func remove(for documentID: UUID) {
        offsets.removeValue(forKey: documentID)
    }
}

public struct RectangularSelection: Equatable, Sendable {
    public let ranges: [NSRange]
    public let startColumn: Int
    public let endColumn: Int

    public init(ranges: [NSRange], startColumn: Int, endColumn: Int) {
        self.ranges = ranges
        self.startColumn = startColumn
        self.endColumn = endColumn
    }
}

/// Converts two UTF-16 caret locations into one same-column range per line.
/// The result intentionally keeps zero-length ranges for short lines so column
/// paste can pad those lines to the requested insertion column.
public enum RectangularSelectionEngine {
    public static func selection(in text: String, anchor: Int, head: Int) -> RectangularSelection {
        let nsText = text as NSString
        let lines = lineRanges(in: nsText)
        let anchorPosition = position(of: anchor, in: lines, textLength: nsText.length)
        let headPosition = position(of: head, in: lines, textLength: nsText.length)
        return selection(
            in: text,
            startLine: min(anchorPosition.line, headPosition.line),
            endLine: max(anchorPosition.line, headPosition.line),
            startColumn: min(anchorPosition.column, headPosition.column),
            endColumn: max(anchorPosition.column, headPosition.column)
        )
    }

    /// Builds a rectangular selection using zero-based line and UTF-16 column
    /// indexes. Columns past a short line are retained as zero-length ranges so
    /// typing and pasting can pad that line to the requested visual column.
    public static func selection(
        in text: String,
        startLine: Int,
        endLine: Int,
        startColumn: Int,
        endColumn: Int
    ) -> RectangularSelection {
        let nsText = text as NSString
        let lines = lineRanges(in: nsText)
        let firstLine = min(max(min(startLine, endLine), 0), lines.count - 1)
        let lastLine = min(max(max(startLine, endLine), firstLine), lines.count - 1)
        let lowerColumn = max(min(startColumn, endColumn), 0)
        let upperColumn = max(max(startColumn, endColumn), lowerColumn)

        let ranges = lines[firstLine...lastLine].map { line -> NSRange in
            let lineLength = line.length
            let rangeStart = min(lowerColumn, lineLength)
            let rangeEnd = min(upperColumn, lineLength)
            return NSRange(
                location: line.location + rangeStart,
                length: max(0, rangeEnd - rangeStart)
            )
        }
        return RectangularSelection(ranges: ranges, startColumn: lowerColumn, endColumn: upperColumn)
    }

    private static func lineRanges(in text: NSString) -> [NSRange] {
        guard text.length > 0 else { return [NSRange(location: 0, length: 0)] }
        var result: [NSRange] = []
        var cursor = 0
        while cursor < text.length {
            let fullRange = text.lineRange(for: NSRange(location: cursor, length: 0))
            var contentEnd = NSMaxRange(fullRange)
            while contentEnd > fullRange.location {
                let character = text.character(at: contentEnd - 1)
                guard character == 10 || character == 13 else { break }
                contentEnd -= 1
            }
            result.append(NSRange(location: fullRange.location, length: contentEnd - fullRange.location))
            cursor = NSMaxRange(fullRange)
        }
        if text.character(at: text.length - 1) == 10 || text.character(at: text.length - 1) == 13 {
            result.append(NSRange(location: text.length, length: 0))
        }
        return result
    }

    private static func position(
        of rawLocation: Int,
        in lines: [NSRange],
        textLength: Int
    ) -> (line: Int, column: Int) {
        let location = min(max(rawLocation, 0), textLength)
        for (index, line) in lines.enumerated() {
            if location <= NSMaxRange(line) {
                return (index, max(0, location - line.location))
            }
        }
        let lastIndex = max(lines.count - 1, 0)
        let last = lines[lastIndex]
        return (lastIndex, last.length)
    }
}

public enum LineEditingAction: String, CaseIterable, Identifiable, Sendable {
    case duplicate
    case delete
    case moveUp
    case moveDown
    case toggleComment
    case indent
    case outdent
    case joinWithNext
    case removeEmptyLines

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .duplicate: "Duplicate Line"
        case .delete: "Delete Line"
        case .moveUp: "Move Line Up"
        case .moveDown: "Move Line Down"
        case .toggleComment: "Toggle Comment"
        case .indent: "Indent"
        case .outdent: "Outdent"
        case .joinWithNext: "Join Lines"
        case .removeEmptyLines: "Remove Empty Lines"
        }
    }
}

public struct TextEditingResult: Equatable, Sendable {
    public let text: String
    public let selection: NSRange

    public init(text: String, selection: NSRange) {
        self.text = text
        self.selection = selection
    }
}

public enum LineEditingEngine {
    public static func apply(
        _ action: LineEditingAction,
        to text: String,
        selection: NSRange,
        language: SyntaxLanguage
    ) -> TextEditingResult {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let safeSelection = NSIntersectionRange(selection, fullRange)
        let probe = safeSelection.length == 0 && safeSelection.location == nsText.length && nsText.length > 0
            ? NSRange(location: safeSelection.location - 1, length: 0)
            : safeSelection
        let linesRange = nsText.lineRange(for: probe)

        switch action {
        case .duplicate:
            let block = nsText.substring(with: linesRange)
            let separator = block.hasSuffix("\n") || linesRange.location == 0 && nsText.length == 0 ? "" : "\n"
            let insertion = separator + block
            let result = NSMutableString(string: text)
            result.insert(insertion, at: NSMaxRange(linesRange))
            return TextEditingResult(
                text: result as String,
                selection: NSRange(location: NSMaxRange(linesRange) + (separator as NSString).length, length: block.utf16.count)
            )

        case .delete:
            let result = nsText.replacingCharacters(in: linesRange, with: "")
            return TextEditingResult(
                text: result,
                selection: NSRange(location: min(linesRange.location, (result as NSString).length), length: 0)
            )

        case .moveUp:
            guard linesRange.location > 0 else {
                return TextEditingResult(text: text, selection: safeSelection)
            }
            let previousRange = nsText.lineRange(for: NSRange(location: linesRange.location - 1, length: 0))
            let previous = nsText.substring(with: previousRange)
            let current = nsText.substring(with: linesRange)
            let union = NSUnionRange(previousRange, linesRange)
            let swapped: String
            if current.hasSuffix("\n") {
                swapped = current + previous
            } else {
                swapped = current + "\n" + String(previous.dropLast())
            }
            let result = nsText.replacingCharacters(in: union, with: swapped)
            let delta = previousRange.length
            return TextEditingResult(
                text: result,
                selection: NSRange(location: max(0, safeSelection.location - delta), length: safeSelection.length)
            )

        case .moveDown:
            guard NSMaxRange(linesRange) < nsText.length else {
                return TextEditingResult(text: text, selection: safeSelection)
            }
            let nextRange = nsText.lineRange(for: NSRange(location: NSMaxRange(linesRange), length: 0))
            let current = nsText.substring(with: linesRange)
            let next = nsText.substring(with: nextRange)
            let union = NSUnionRange(linesRange, nextRange)
            let swapped: String
            if next.hasSuffix("\n") {
                swapped = next + current
            } else {
                swapped = next + "\n" + String(current.dropLast())
            }
            let result = nsText.replacingCharacters(in: union, with: swapped)
            let delta = nextRange.length + (next.hasSuffix("\n") ? 0 : 1)
            return TextEditingResult(
                text: result,
                selection: NSRange(location: safeSelection.location + delta, length: safeSelection.length)
            )

        case .toggleComment:
            let prefix = commentPrefix(for: language)
            let block = nsText.substring(with: linesRange)
            let lines = block.components(separatedBy: "\n")
            let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let shouldUncomment = !nonEmpty.isEmpty && nonEmpty.allSatisfy {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
            }
            let transformed = lines.map { line -> String in
                guard !line.isEmpty else { return line }
                let whitespaceCount = line.prefix(while: { $0 == " " || $0 == "\t" }).count
                let index = line.index(line.startIndex, offsetBy: whitespaceCount)
                if shouldUncomment, line[index...].hasPrefix(prefix) {
                    let afterPrefix = line.index(index, offsetBy: prefix.count)
                    var remainder = String(line[afterPrefix...])
                    if remainder.hasPrefix(" ") { remainder.removeFirst() }
                    return String(line[..<index]) + remainder
                }
                return String(line[..<index]) + prefix + " " + String(line[index...])
            }.joined(separator: "\n")
            let result = nsText.replacingCharacters(in: linesRange, with: transformed)
            return TextEditingResult(
                text: result,
                selection: NSRange(location: linesRange.location, length: (transformed as NSString).length)
            )

        case .indent:
            let block = nsText.substring(with: linesRange)
            let transformed = block.components(separatedBy: "\n")
                .map { $0.isEmpty ? $0 : "    " + $0 }
                .joined(separator: "\n")
            let result = nsText.replacingCharacters(in: linesRange, with: transformed)
            return TextEditingResult(
                text: result,
                selection: NSRange(location: linesRange.location, length: (transformed as NSString).length)
            )

        case .outdent:
            let block = nsText.substring(with: linesRange)
            let transformed = block.components(separatedBy: "\n").map { line -> String in
                if line.hasPrefix("\t") { return String(line.dropFirst()) }
                let spaces = min(line.prefix(while: { $0 == " " }).count, 4)
                return String(line.dropFirst(spaces))
            }.joined(separator: "\n")
            let result = nsText.replacingCharacters(in: linesRange, with: transformed)
            return TextEditingResult(
                text: result,
                selection: NSRange(location: linesRange.location, length: (transformed as NSString).length)
            )

        case .joinWithNext:
            let block = nsText.substring(with: linesRange)
            guard block.contains("\n") else { return TextEditingResult(text: text, selection: safeSelection) }
            let transformed = block.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            let result = nsText.replacingCharacters(in: linesRange, with: transformed)
            return TextEditingResult(text: result, selection: NSRange(location: linesRange.location, length: (transformed as NSString).length))

        case .removeEmptyLines:
            let block = nsText.substring(with: linesRange)
            let transformed = block.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            guard transformed != block else { return TextEditingResult(text: text, selection: safeSelection) }
            let result = nsText.replacingCharacters(in: linesRange, with: transformed)
            return TextEditingResult(text: result, selection: NSRange(location: linesRange.location, length: (transformed as NSString).length))
        }
    }

    private static func commentPrefix(for language: SyntaxLanguage) -> String {
        switch language {
        case .python, .shell, .yaml, .toml: "#"
        case .sql: "--"
        case .plainText, .markdown: "#"
        default: "//"
        }
    }
}

public enum ColumnEditingEngine {
    public static func apply(
        to text: String,
        startLine: Int,
        endLine: Int,
        column: Int,
        value: String,
        overwrite: Bool = false
    ) -> TextEditingResult {
        var lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else {
            return TextEditingResult(text: text, selection: NSRange(location: 0, length: 0))
        }
        let lower = max(1, min(startLine, endLine))
        let upper = min(lines.count, max(startLine, endLine))
        let targetColumn = max(1, column) - 1
        guard lower <= upper else {
            return TextEditingResult(text: text, selection: NSRange(location: 0, length: 0))
        }

        for lineNumber in lower...upper {
            var line = lines[lineNumber - 1]
            let characterCount = line.count
            if characterCount < targetColumn {
                line += String(repeating: " ", count: targetColumn - characterCount)
            }
            let index = line.index(line.startIndex, offsetBy: min(targetColumn, line.count))
            if overwrite, index < line.endIndex {
                let replaceEnd = line.index(index, offsetBy: min(value.count, line.distance(from: index, to: line.endIndex)))
                line.replaceSubrange(index..<replaceEnd, with: value)
            } else {
                line.insert(contentsOf: value, at: index)
            }
            lines[lineNumber - 1] = line
        }

        let result = lines.joined(separator: "\n")
        let prefix = lines.prefix(lower - 1).joined(separator: "\n")
        let location = (prefix as NSString).length + (lower > 1 ? 1 : 0) + targetColumn
        return TextEditingResult(
            text: result,
            selection: NSRange(location: min(location, (result as NSString).length), length: (value as NSString).length)
        )
    }
}

/// 独立于界面会话的临时文档恢复记录。
///
/// 字段使用稳定的字符串值，避免将来增加枚举成员时导致旧版恢复文件无法解码。
/// Raw enum values keep older sessions readable when presentation choices change.
struct WorkspaceSessionDocument: Codable, Equatable {
    let id: UUID
    let title: String
    let scratchContent: String?
    let path: String?
    let securityScopedBookmark: Data?
    let language: String?
    let encoding: String?
    let lineEnding: String?
    let bookmarks: Set<Int>?
    let groupID: UUID?
    let isPinned: Bool?
}

public struct WorkspaceSessionGroup: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let color: String?
    public var parentID: UUID?

    public init(id: UUID, name: String, color: String?, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.parentID = parentID
    }
}

struct WorkspaceSessionSnapshot: Codable, Equatable {
    let documents: [WorkspaceSessionDocument]
    let activeID: UUID?
    let groups: [WorkspaceSessionGroup]?
    let selectedGroupID: UUID?
}

/// Mirrors the legacy defaults session to an atomic file and a previous version.
/// Failed decoding never becomes an empty session; original bytes are retained.
final class WorkspaceSessionArchive {
    let directoryURL: URL
    private let defaults: UserDefaults
    private let key: String
    private let fileManager = FileManager.default

    init(directoryURL: URL, defaults: UserDefaults, key: String) {
        self.directoryURL = directoryURL
        self.defaults = defaults
        self.key = key
    }

    private var primaryURL: URL { directoryURL.appendingPathComponent("session.json") }
    private var backupURL: URL { directoryURL.appendingPathComponent("session.backup.json") }

    func load() throws -> WorkspaceSessionSnapshot? {
        let candidates = [
            try readIfPresent(primaryURL), defaults.data(forKey: key),
            try readIfPresent(backupURL), defaults.data(forKey: key + ".backup")
        ].compactMap { $0 }
        for data in candidates {
            if let session = try? decode(data) {
                // Preserve the exact pre-migration session before the first write.
                let migrationURL = directoryURL.appendingPathComponent("session.before-migration.json")
                if !fileManager.fileExists(atPath: migrationURL.path) {
                    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                    try data.write(to: migrationURL, options: .atomic)
                }
                return session
            }
            try preserveUnreadable(data)
        }
        if !candidates.isEmpty { throw CocoaError(.coderReadCorrupt) }
        return nil
    }

    func save(_ session: WorkspaceSessionSnapshot) throws {
        let data = try JSONEncoder().encode(session)
        _ = try decode(data)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let previous = try readIfPresent(primaryURL) ?? defaults.data(forKey: key)
        if let previous, previous != data {
            if (try? decode(previous)) != nil {
                try previous.write(to: backupURL, options: .atomic)
                defaults.set(previous, forKey: key + ".backup")
            } else {
                try preserveUnreadable(previous)
            }
        }
        try data.write(to: primaryURL, options: .atomic)
        defaults.set(data, forKey: key)
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func decode(_ data: Data) throws -> WorkspaceSessionSnapshot {
        let session = try JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: data)
        guard Set(session.documents.map(\.id)).count == session.documents.count,
              Set((session.groups ?? []).map(\.id)).count == (session.groups ?? []).count,
              session.documents.allSatisfy({ $0.path != nil || $0.scratchContent != nil })
        else { throw CocoaError(.coderReadCorrupt) }
        return session
    }

    private func preserveUnreadable(_ data: Data) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(
            to: directoryURL.appendingPathComponent("session.unreadable-\(UUID().uuidString).json"),
            options: .atomic
        )
    }
}

public struct ScratchRecoveryRecord: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: UUID
    public var title: String
    public var content: String
    public var language: String
    public var encoding: String
    public var lineEnding: String
    public var bookmarks: Set<Int>
    public var groupID: UUID?
    public var groupName: String?
    public var groupColor: String?
    public var groupAncestors: [WorkspaceSessionGroup]?
    public var isPinned: Bool
    public var updatedAt: Date

    public init(
        schemaVersion: Int = 1,
        id: UUID,
        title: String,
        content: String,
        language: String,
        encoding: String,
        lineEnding: String,
        bookmarks: Set<Int> = [],
        groupID: UUID? = nil,
        groupName: String? = nil,
        groupColor: String? = nil,
        groupAncestors: [WorkspaceSessionGroup]? = nil,
        isPinned: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.content = content
        self.language = language
        self.encoding = encoding
        self.lineEnding = lineEnding
        self.bookmarks = bookmarks
        self.groupID = groupID
        self.groupName = groupName
        self.groupColor = groupColor
        self.groupAncestors = groupAncestors
        self.isPinned = isPinned
        self.updatedAt = updatedAt
    }
}

/// 将每个临时文档单独原子写入磁盘，并保留上一个可读版本。
public final class ScratchRecoveryStore {
    public let directoryURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func save(_ record: ScratchRecoveryRecord) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let primaryURL = url(for: record.id)
        let backupURL = backupURL(for: record.id)
        let data = try encoder.encode(record)

        if fileManager.fileExists(atPath: primaryURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: primaryURL, to: backupURL)
        }
        try data.write(to: primaryURL, options: [.atomic])
    }

    public func remove(id: UUID) {
        try? fileManager.removeItem(at: url(for: id))
        try? fileManager.removeItem(at: backupURL(for: id))
    }

    public func loadAll() -> [ScratchRecoveryRecord] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let identifiers = Set(files.compactMap { file -> UUID? in
            let name = file.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: ".recovery", with: "")
                .replacingOccurrences(of: ".backup", with: "")
            return UUID(uuidString: name)
        })

        return identifiers.compactMap(load(id:)).sorted { $0.updatedAt < $1.updatedAt }
    }

    private func load(id: UUID) -> ScratchRecoveryRecord? {
        for candidate in [url(for: id), backupURL(for: id)] {
            guard let data = try? Data(contentsOf: candidate),
                  let record = try? decoder.decode(ScratchRecoveryRecord.self, from: data)
            else { continue }
            return record
        }
        return nil
    }

    private func url(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).recovery.json")
    }

    private func backupURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString).backup.json")
    }
}

public struct ReleaseNoteSection: Equatable, Sendable {
    public let title: String
    public let items: [String]

    public init(title: String, items: [String]) {
        self.title = title
        self.items = items
    }
}

public struct ReleaseNoteVersion: Identifiable, Equatable, Sendable {
    public var id: String { "\(version)-\(date)" }
    public let version: String
    public let date: String
    public let sections: [ReleaseNoteSection]

    public init(version: String, date: String, sections: [ReleaseNoteSection]) {
        self.version = version
        self.date = date
        self.sections = sections
    }
}

/// 把随应用发布的 CHANGELOG Markdown 转换成稳定的结构化数据，
/// 由原生界面负责排版，避免系统 Markdown 富文本丢失段落层级。
public enum ReleaseNotesParser {
    public static func parse(_ markdown: String) -> [ReleaseNoteVersion] {
        struct SectionBuilder {
            var title: String
            var items: [String]
        }
        struct VersionBuilder {
            var version: String
            var date: String
            var sections: [SectionBuilder]
        }

        var releases: [ReleaseNoteVersion] = []
        var current: VersionBuilder?

        func finishCurrent() {
            guard let current else { return }
            let sections = current.sections
                .filter { !$0.items.isEmpty }
                .map { ReleaseNoteSection(title: $0.title, items: $0.items) }
            guard !sections.isEmpty else { return }
            releases.append(ReleaseNoteVersion(
                version: current.version,
                date: current.date,
                sections: sections
            ))
        }

        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let header = versionHeader(line) {
                finishCurrent()
                current = VersionBuilder(version: header.version, date: header.date, sections: [])
            } else if line.hasPrefix("### "), current != nil {
                current?.sections.append(SectionBuilder(
                    title: String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces),
                    items: []
                ))
            } else if line.hasPrefix("- "), var version = current {
                if version.sections.isEmpty {
                    version.sections.append(SectionBuilder(title: "其他改进", items: []))
                }
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    version.sections[version.sections.count - 1].items.append(item)
                }
                current = version
            }
        }
        finishCurrent()
        return releases
    }

    private static func versionHeader(_ line: String) -> (version: String, date: String)? {
        guard line.hasPrefix("## "), !line.hasPrefix("### ") else { return nil }
        let header = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let pairs: [(Character, Character)] = [("（", "）"), ("(", ")")]

        for (opening, closing) in pairs {
            guard header.last == closing,
                  let openingIndex = header.lastIndex(of: opening)
            else { continue }
            let version = String(header[..<openingIndex]).trimmingCharacters(in: .whitespaces)
            let dateStart = header.index(after: openingIndex)
            let dateEnd = header.index(before: header.endIndex)
            let date = String(header[dateStart..<dateEnd]).trimmingCharacters(in: .whitespaces)
            guard version.first?.isNumber == true, !date.isEmpty else { return nil }
            return (version, date)
        }
        return nil
    }
}

// MARK: - Large-file policy (Notepad++ Performance page)

/// Mirrors Notepad++'s large-file shedding: above a size threshold, turn off
/// wrap / lexical colouring / brace matching so the editor stays interactive.
public enum LargeFilePolicy: Sendable {
    /// Same order of magnitude as Notepad++ `NPP_STYLING_FILESIZE_LIMIT_DEFAULT`.
    public static let hugeByteThreshold = 200 * 1024 * 1024
    /// Soft threshold where TextKit work is deferred (colouring, folds, braces).
    public static let largeUTF16Threshold = 300_000
    /// Virtual Select All kicks in well below the large-file tier.
    public static let virtualSelectAllUTF16Threshold = 4_096
    public static let jsonHighlightUTF16Limit = 2_000_000

    public enum Tier: String, Sendable {
        case normal
        case large
        case huge
    }

    public static func tier(byteCount: Int, utf16Length: Int) -> Tier {
        if byteCount >= hugeByteThreshold || utf16Length >= hugeByteThreshold / 2 {
            return .huge
        }
        if utf16Length >= largeUTF16Threshold {
            return .large
        }
        return .normal
    }

    public static func disablesWordWrap(_ tier: Tier) -> Bool {
        tier == .huge
    }

    public static func disablesSyntaxHighlight(_ tier: Tier, language: SyntaxLanguage) -> Bool {
        switch tier {
        case .normal:
            return false
        case .large:
            // JSON keeps a higher colouring budget for common data files.
            if language == .json || language == .jsonc {
                return false
            }
            return true
        case .huge:
            return true
        }
    }

    public static func disablesBracketMatch(_ tier: Tier) -> Bool {
        tier != .normal
    }

    public static func disablesJSONFolding(_ tier: Tier) -> Bool {
        tier == .huge
    }

    public static func allowsJSONHighlight(utf16Length: Int) -> Bool {
        utf16Length <= jsonHighlightUTF16Limit
    }
}

// MARK: - Function List

public struct FunctionListSymbol: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let line: Int
    public let utf16Location: Int

    public init(name: String, detail: String, line: Int, utf16Location: Int) {
        self.name = name
        self.detail = detail
        self.line = line
        self.utf16Location = utf16Location
        self.id = "\(line):\(utf16Location):\(name)"
    }
}

public enum FunctionListEngine: Sendable {
    public static func symbols(in text: String, language: SyntaxLanguage) -> [FunctionListSymbol] {
        guard !text.isEmpty else { return [] }
        let patterns = patterns(for: language)
        guard !patterns.isEmpty else { return [] }

        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        var found: [FunctionListSymbol] = []
        var seen = Set<String>()

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                continue
            }
            regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let match, match.numberOfRanges >= 2 else { return }
                let nameRange = match.range(at: 1)
                guard nameRange.location != NSNotFound, nameRange.length > 0 else { return }
                let name = nsText.substring(with: nameRange)
                let key = "\(match.range.location):\(name)"
                guard seen.insert(key).inserted else { return }
                let line = lineNumber(of: match.range.location, in: nsText)
                let detail = nsText.substring(with: match.range)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                found.append(
                    FunctionListSymbol(
                        name: name,
                        detail: String(detail.prefix(120)),
                        line: line,
                        utf16Location: match.range.location
                    )
                )
            }
        }

        return found.sorted {
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.utf16Location < $1.utf16Location
        }
    }

    private static func patterns(for language: SyntaxLanguage) -> [String] {
        switch language {
        case .swift:
            return [
                #"^\s*(?:(?:public|private|internal|open|fileprivate|static|class|mutating|nonmutating|override|final|async)\s+)*func\s+([A-Za-z_][\w]*)\s*(?:<[^>]*>)?\s*\("#,
                #"^\s*(?:(?:public|private|internal|open|fileprivate)\s+)?(?:final\s+)?(?:class|struct|enum|actor|protocol)\s+([A-Za-z_][\w]*)"#
            ]
        case .python:
            return [
                #"^\s*(?:async\s+)?def\s+([A-Za-z_][\w]*)\s*\("#,
                #"^\s*class\s+([A-Za-z_][\w]*)\s*(?:[:(])"#
            ]
        case .javascript, .typescript:
            return [
                #"^\s*(?:export\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*\("#,
                #"^\s*(?:export\s+)?(?:default\s+)?(?:abstract\s+)?(?:class)\s+([A-Za-z_$][\w$]*)"#,
                #"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>"#
            ]
        case .c, .cpp, .objectiveC:
            return [
                #"^\s*(?:[-+]?\s*\([^)]+\)\s*)?([A-Za-z_][\w]*)\s*\([^;]*\)\s*(?:const)?\s*\{?\s*$"#,
                #"^\s*(?:class|struct|enum|@interface|@implementation)\s+([A-Za-z_][\w]*)"#
            ]
        case .shell:
            return [#"^\s*(?:function\s+)?([A-Za-z_][\w]*)\s*\(\s*\)\s*\{"#]
        case .sql:
            return [#"^\s*CREATE\s+(?:OR\s+REPLACE\s+)?(?:FUNCTION|PROCEDURE)\s+([A-Za-z_][\w]*)"#]
        default:
            return []
        }
    }

    private static func lineNumber(of utf16Offset: Int, in text: NSString) -> Int {
        var line = 1
        var index = 0
        while index < utf16Offset && index < text.length {
            let ch = text.character(at: index)
            if ch == 10 { // \n
                line += 1
            } else if ch == 13 { // \r
                line += 1
                if index + 1 < utf16Offset && text.character(at: index + 1) == 10 {
                    index += 1
                }
            }
            index += 1
        }
        return line
    }
}
