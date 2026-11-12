import Foundation
import Combine

enum DocumentEncoding: String, CaseIterable, Codable, Identifiable {
    case utf8
    case utf16
    case utf16LittleEndian
    case utf16BigEndian
    case isoLatin1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .utf8: "UTF-8"
        case .utf16: "UTF-16"
        case .utf16LittleEndian: "UTF-16 LE"
        case .utf16BigEndian: "UTF-16 BE"
        case .isoLatin1: "ISO-8859-1"
        }
    }

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8: .utf8
        case .utf16: .utf16
        case .utf16LittleEndian: .utf16LittleEndian
        case .utf16BigEndian: .utf16BigEndian
        case .isoLatin1: .isoLatin1
        }
    }
}

enum LineEnding: String, CaseIterable, Codable, Identifiable {
    case lf
    case crlf
    case cr

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .lf: "Unix (LF)"
        case .crlf: "Windows (CR LF)"
        case .cr: "Classic Mac (CR)"
        }
    }

    var sequence: String {
        switch self {
        case .lf: "\n"
        case .crlf: "\r\n"
        case .cr: "\r"
        }
    }

    static func detect(in text: String) -> LineEnding {
        if text.contains("\r\n") { return .crlf }
        if text.contains("\r") { return .cr }
        return .lf
    }
}

final class EditorDocument: ObservableObject, Identifiable {
    let id: UUID

    @Published var title: String
    @Published var content: String {
        didSet {
            contentRevision &+= 1
            cachedLineStartsRevision = nil
            cachedLineStarts.removeAll(keepingCapacity: true)
            cachedLineStarts.append(0)
            guard !isApplyingExternalChange, fileAccessError == nil else { return }
            isDirty = true
        }
    }
    /// Monotonic content generation used by the UIKit editor bridge. It lets
    /// selection-only SwiftUI updates skip an O(n) whole-document comparison.
    private(set) var contentRevision: UInt = 0
    @Published var fileURL: URL?
    /// Keep inaccessible files in their original tabs/groups without treating
    /// an unloaded buffer as an empty, writable document.
    @Published var fileAccessError: String?
    var securityScopedBookmark: Data?
    @Published var isDirty: Bool
    @Published var selection: NSRange
    // Kept with the document itself so tab switches can read the latest
    // viewport even when the workspace does not publish every scroll event.
    var scrollOffset: CGPoint = .zero
    var markdownScrollPosition: MarkdownScrollPosition?
    @Published var bookmarks: Set<Int>
    @Published var groupID: UUID?
    @Published var isPinned: Bool
    @Published var language: SyntaxLanguage
    @Published var encoding: DocumentEncoding {
        didSet {
            guard !isApplyingExternalChange, fileAccessError == nil else { return }
            isDirty = true
        }
    }
    @Published var lineEnding: LineEnding {
        didSet {
            guard !isApplyingExternalChange, fileAccessError == nil else { return }
            isDirty = true
        }
    }

    // Status-bar and document-info views are recomputed whenever selection
    // changes.  Recounting a multi-megabyte buffer for every Command-A/caret
    // update is surprisingly expensive (SwiftUI reevaluates those views even
    // though the content did not change).  Keep the derived values keyed by
    // the content revision; this mirrors the line-count cache used by native
    // editors and makes selection-only updates O(1).
    private var cachedStatisticsRevision: UInt?
    private var cachedLineCount = 1
    private var cachedWordCount = 0
    private var cachedCharacterCount = 0
    private var cachedByteCount = 0
    private var cachedLineStartsRevision: UInt?
    private var cachedLineStarts: [Int] = [0]

    private var isApplyingExternalChange = false

    private func refreshStatisticsIfNeeded() {
        guard cachedStatisticsRevision != contentRevision else { return }
        cachedLineCount = TextStatistics.lineCount(in: content)
        cachedWordCount = TextStatistics.wordCount(in: content)
        cachedCharacterCount = TextStatistics.characterCount(in: content)
        cachedByteCount = TextStatistics.byteCount(in: content)
        cachedStatisticsRevision = contentRevision
    }

    var lineCount: Int {
        refreshStatisticsIfNeeded()
        return cachedLineCount
    }

    var wordCount: Int {
        refreshStatisticsIfNeeded()
        return cachedWordCount
    }

    var characterCount: Int {
        refreshStatisticsIfNeeded()
        return cachedCharacterCount
    }

    var byteCount: Int {
        refreshStatisticsIfNeeded()
        return cachedByteCount
    }

    private func refreshLineStartsIfNeeded() {
        guard cachedLineStartsRevision != contentRevision else { return }
        var starts = [0]
        starts.reserveCapacity(max(1, (content as NSString).length / 40))
        for (index, scalar) in content.utf16.enumerated() where scalar == 10 {
            starts.append(index + 1)
        }
        cachedLineStarts = starts
        cachedLineStartsRevision = contentRevision
    }

    func lineAndColumn(atUTF16Location location: Int) -> (line: Int, column: Int) {
        refreshLineStartsIfNeeded()
        let length = (content as NSString).length
        let safeLocation = min(max(location, 0), length)
        var low = 0
        var high = cachedLineStarts.count
        while low < high {
            let middle = low + (high - low) / 2
            if cachedLineStarts[middle] <= safeLocation { low = middle + 1 }
            else { high = middle }
        }
        let lineIndex = max(0, low - 1)
        return (lineIndex + 1, safeLocation - cachedLineStarts[lineIndex] + 1)
    }

    init(
        id: UUID = UUID(),
        title: String,
        content: String = "",
        fileURL: URL? = nil,
        isDirty: Bool = false,
        selection: NSRange = NSRange(location: 0, length: 0),
        bookmarks: Set<Int> = [],
        groupID: UUID? = nil,
        isPinned: Bool = false,
        language: SyntaxLanguage? = nil,
        encoding: DocumentEncoding = .utf8,
        lineEnding: LineEnding = .lf
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.fileURL = fileURL
        self.isDirty = isDirty
        self.selection = selection
        self.bookmarks = bookmarks
        self.groupID = groupID
        self.isPinned = isPinned
        self.language = language ?? SyntaxLanguage.detect(filename: title)
        self.encoding = encoding
        self.lineEnding = lineEnding
    }

    var textForSaving: String {
        guard lineEnding != .lf else { return content }
        return content.replacingOccurrences(of: "\n", with: lineEnding.sequence)
    }

    func updateFromDisk(_ newContent: String) {
        isApplyingExternalChange = true
        // Always bump the revision, even when the decoded string equals the
        // in-memory buffer. External reloads must force the UIKit bridge to
        // re-read the binding; skipping that left the old TextView text on
        // screen while the model looked “up to date”.
        if content == newContent {
            contentRevision &+= 1
            objectWillChange.send()
        } else {
            content = newContent
        }
        isApplyingExternalChange = false
        isDirty = false
    }

    /// Apply encoding / line-ending metadata from disk without marking dirty
    /// or scheduling autosave side-effects mid-reload.
    func applyDiskMetadata(encoding: DocumentEncoding, lineEnding: LineEnding) {
        isApplyingExternalChange = true
        self.encoding = encoding
        self.lineEnding = lineEnding
        isApplyingExternalChange = false
    }

    func markSaved(at url: URL? = nil) {
        if let url {
            fileURL = url
            title = url.lastPathComponent
            language = SyntaxLanguage.detect(filename: title)
        }
        isDirty = false
    }

    var currentLine: Int {
        lineAndColumn(atUTF16Location: selection.location).line
    }

    func toggleBookmark() {
        let line = currentLine
        if bookmarks.contains(line) {
            bookmarks.remove(line)
        } else {
            bookmarks.insert(line)
        }
    }

    func goToLine(_ requestedLine: Int) {
        // Reuse the revision-keyed line-start index instead of walking every
        // preceding line. This keeps Go To Line responsive in multi-megabyte
        // documents, including when the requested line is near EOF.
        refreshLineStartsIfNeeded()
        let target = max(1, min(requestedLine, cachedLineStarts.count))
        let location = cachedLineStarts[target - 1]
        let nsText = content as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: min(location, nsText.length), length: 0))
        let lineText = nsText.substring(with: lineRange)
        selection = NSRange(
            location: lineRange.location,
            length: max(0, lineRange.length - (lineText.hasSuffix("\n") ? 1 : 0))
        )
    }

    func goToAdjacentBookmark(forward: Bool) {
        let ordered = bookmarks.sorted()
        guard !ordered.isEmpty else { return }
        let destination: Int
        if forward {
            destination = ordered.first(where: { $0 > currentLine }) ?? ordered[0]
        } else {
            destination = ordered.last(where: { $0 < currentLine }) ?? ordered[ordered.count - 1]
        }
        goToLine(destination)
    }
}

extension EditorDocument {
    struct DecodedFile {
        let text: String
        let encoding: DocumentEncoding
        let lineEnding: LineEnding
    }

    static func decode(_ data: Data) throws -> DecodedFile {
        let candidates: [(DocumentEncoding, String.Encoding)] = [
            (.utf8, .utf8),
            (.utf16, .utf16),
            (.utf16LittleEndian, .utf16LittleEndian),
            (.utf16BigEndian, .utf16BigEndian),
            (.isoLatin1, .isoLatin1)
        ]

        for (documentEncoding, stringEncoding) in candidates {
            if let raw = String(data: data, encoding: stringEncoding) {
                let ending = LineEnding.detect(in: raw)
                // Most source files already use LF. Avoid allocating one or
                // two complete replacement strings on that hot path; this is
                // noticeable when opening multi-megabyte documents.
                let normalized: String
                if raw.contains("\r") {
                    normalized = raw
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                } else {
                    normalized = raw
                }
                return DecodedFile(text: normalized, encoding: documentEncoding, lineEnding: ending)
            }
        }

        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
