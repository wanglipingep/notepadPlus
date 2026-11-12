import SwiftUI
import UniformTypeIdentifiers
import Darwin
import ImageIO
#if canImport(UIKit)
import UIKit
#endif
#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif

// MARK: - Search File (Raycast Search Files: Spotlight MDQuery / NSMetadataQuery)

enum FileSearchScope: String, CaseIterable, Identifiable {
    case thisMac
    case home
    case recent
    case authorized

    var id: String { rawValue }

    var title: String {
        switch self {
        case .thisMac: "整台 Mac"
        case .home: "个人文件夹"
        case .recent: "最近文件"
        case .authorized: "已授权位置"
        }
    }
}

struct FileSearchHit: Identifiable, Hashable {
    let id: String
    let url: URL
    let name: String
    let directory: String
    let score: Int
    let source: FileSearchScope
}

/// Raycast Search Files (from REA strings on Raycast.app):
/// `FileSearchQuery` → `MDQueryCreate` / `MDQuerySetSearchScope` /
/// `MDQuerySetMaxCount` / timeout, scopes `Computer` · `Home` · custom dirs,
/// query types name / nameAndContents. We mirror that with `NSMetadataQuery`
/// (Foundation wrapper over MDQuery) now that the Mac Catalyst build is
/// unsandboxed like Raycast.
@MainActor
final class FileSearchController: ObservableObject {
    @Published var query = ""
    @Published var scope: FileSearchScope = .thisMac
    @Published private(set) var results: [FileSearchHit] = []
    @Published var selectedID: String?
    @Published private(set) var previewText = ""
    @Published private(set) var previewImage: UIImage?
    @Published private(set) var metadata: FileSearchMetadata?
    @Published private(set) var isSearching = false
    @Published var statusMessage = ""

    /// Scopes shown in the Raycast-like picker (no authorize friction).
    static let pickerScopes: [FileSearchScope] = [.thisMac, .home, .recent]

    private weak var workspace: WorkspaceStore?
    private var searchTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var searchGeneration = 0
    private let spotlight = SpotlightFileSearcher()

    struct FileSearchMetadata {
        let name: String
        let wherePath: String
        let typeName: String
        let size: String
        let created: String
        let modified: String
    }

    func attach(workspace: WorkspaceStore) {
        self.workspace = workspace
        runSearch()
    }

    func scheduleSearch() {
        searchTask?.cancel()
        let query = self.query
        let scope = self.scope
        searchTask = Task { @MainActor in
            // Raycast feels instant — keep debounce minimal.
            let delay: UInt64 = scope == .recent ? 25 : 40
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            self.query = query
            self.scope = scope
            self.runSearch()
        }
    }

    func select(_ id: String) {
        selectedID = id
        schedulePreview(for: id)
    }

    func selectedHit() -> FileSearchHit? {
        results.first(where: { $0.id == selectedID }) ?? results.first
    }

    func stop() {
        searchTask?.cancel()
        previewTask?.cancel()
        spotlight.stop()
    }

    private func runSearch() {
        guard let workspace else { return }
        searchGeneration &+= 1
        let generation = searchGeneration
        spotlight.stop()

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = self.scope

        let parsed = FileSearchQueryParser.parse(q)
        // Instant paint from recent/open tabs only — do not walk workspace
        // files on every keystroke (that was a major lag source).
        let local = FileSearchEngine.localHits(
            parsed: parsed,
            scope: scope,
            openURLs: workspace.documents.compactMap(\.fileURL),
            recent: workspace.recentFiles,
            workspaceFiles: []
        )

        // Recent / empty: instant local list.
        if scope == .recent || parsed.isEmpty {
            publish(results: Array(local.prefix(60)), generation: generation, searching: false)
            statusMessage = parsed.isEmpty && scope != .recent
                ? "输入关键字；空格多词、类型词，例如：天山 周报 pdf"
                : ""
            return
        }

        publish(results: Array(local.prefix(20)), generation: generation, searching: true)
        statusMessage = "正在搜索…"

        let localCopy = local
        // Whole-Mac Spotlight can be heavy; hard-cap and early-kill mdfind.
        let timeout: TimeInterval = scope == .thisMac ? 0.85 : 1.1
        spotlight.search(
            parsed: parsed,
            scope: scope == .authorized ? .thisMac : scope,
            extraFolders: [],
            limit: 50,
            timeout: timeout
        ) { [weak self] spotlightHits, timedOut in
            Task { @MainActor in
                guard let self, generation == self.searchGeneration else { return }
                let merged = FileSearchEngine.merge(local: localCopy, deep: spotlightHits, limit: 50)
                self.publish(results: merged, generation: generation, searching: false)
                if merged.isEmpty {
                    self.statusMessage = "没有匹配。可换词或类型（pdf / excel）。"
                } else if timedOut {
                    self.statusMessage = "已返回前 \(merged.count) 条"
                } else {
                    self.statusMessage = "找到 \(merged.count) 个文件"
                }
            }
        }
    }

    private func publish(results: [FileSearchHit], generation: Int, searching: Bool) {
        guard generation == searchGeneration else { return }
        self.results = results
        self.isSearching = searching
        if let selectedID, results.contains(where: { $0.id == selectedID }) {
            if previewText.isEmpty, previewImage == nil { schedulePreview(for: selectedID) }
        } else {
            selectedID = results.first?.id
            previewText = ""
            previewImage = nil
            metadata = nil
            if let selectedID {
                schedulePreview(for: selectedID)
            }
        }
    }

    private func schedulePreview(for id: String) {
        previewTask?.cancel()
        guard let hit = results.first(where: { $0.id == id }) else {
            previewText = ""
            previewImage = nil
            metadata = nil
            return
        }
        let url = hit.url
        previewImage = nil
        previewText = ""
        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, selectedID == id else { return }
            let snapshot = await FileSearchEngine.previewBundle(for: url)
            guard selectedID == id else { return }
            metadata = snapshot.metadata
            previewImage = snapshot.image
            previewText = snapshot.text
        }
    }
}

struct FileTypeFilter: Hashable {
    let label: String
    let extensions: [String]
    let contentTypes: [String]
}

struct ParsedFileSearchQuery: Equatable {
    var nameTokens: [String]
    var typeFilters: [FileTypeFilter]
    var searchContents: Bool

    var isEmpty: Bool { nameTokens.isEmpty && typeFilters.isEmpty }
}

/// Space-separated tokens + type keywords (pdf / excel / xls …), Raycast-style.
enum FileSearchQueryParser {
    static func tokens(from raw: String) -> [String] {
        parse(raw).nameTokens
    }

    static func parse(_ raw: String) -> ParsedFileSearchQuery {
        let parts = splitTokens(raw)
        var nameTokens: [String] = []
        var types: [FileTypeFilter] = []
        var searchContents = false
        var seenType = Set<String>()

        for part in parts {
            var token = part
            let lower = token.lowercased()
            if lower.hasPrefix("content:") || lower.hasPrefix("内容:") {
                searchContents = true
                let stripped = String(token.split(separator: ":", maxSplits: 1).last ?? "")
                if !stripped.isEmpty { nameTokens.append(stripped) }
                continue
            }
            if lower.hasPrefix("kind:") || lower.hasPrefix("type:") || lower.hasPrefix("类型:") {
                token = String(token.split(separator: ":", maxSplits: 1).last ?? "")
            }
            if token.hasPrefix(".") { token = String(token.dropFirst()) }
            if let filter = typeFilter(for: token), seenType.insert(filter.label).inserted {
                types.append(filter)
            } else if !token.isEmpty {
                nameTokens.append(token)
            }
        }
        return ParsedFileSearchQuery(
            nameTokens: nameTokens,
            typeFilters: types,
            searchContents: searchContents
        )
    }

    private static func splitTokens(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        var inQuotes = false
        for ch in trimmed {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch.isWhitespace, !inQuotes {
                let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !piece.isEmpty { tokens.append(piece) }
                current = ""
                continue
            }
            current.append(ch)
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { tokens.append(tail) }
        return tokens
    }

    static func typeFilter(for raw: String) -> FileTypeFilter? {
        switch raw.lowercased() {
        case "pdf":
            return FileTypeFilter(label: "pdf", extensions: ["pdf"], contentTypes: ["com.adobe.pdf"])
        case "excel", "xls", "xlsx", "xlsm", "csv", "表格":
            return FileTypeFilter(
                label: "excel",
                extensions: ["xls", "xlsx", "xlsm", "csv"],
                contentTypes: [
                    "com.microsoft.excel.xls",
                    "org.openxmlformats.spreadsheetml.sheet",
                    "public.comma-separated-values-text"
                ]
            )
        case "word", "doc", "docx":
            return FileTypeFilter(
                label: "word",
                extensions: ["doc", "docx"],
                contentTypes: [
                    "com.microsoft.word.doc",
                    "org.openxmlformats.wordprocessingml.document"
                ]
            )
        case "ppt", "pptx", "powerpoint", "key":
            return FileTypeFilter(
                label: "ppt",
                extensions: ["ppt", "pptx", "key"],
                contentTypes: [
                    "com.microsoft.powerpoint.ppt",
                    "org.openxmlformats.presentationml.presentation",
                    "com.apple.keynote.key"
                ]
            )
        case "txt", "text", "文本":
            return FileTypeFilter(label: "txt", extensions: ["txt", "text", "log"], contentTypes: ["public.plain-text"])
        case "md", "markdown":
            return FileTypeFilter(label: "md", extensions: ["md", "markdown"], contentTypes: ["net.daringfireball.markdown"])
        case "json":
            return FileTypeFilter(label: "json", extensions: ["json", "jsonc"], contentTypes: ["public.json"])
        case "xml", "plist":
            return FileTypeFilter(label: "xml", extensions: ["xml", "plist"], contentTypes: ["public.xml", "com.apple.property-list"])
        case "html", "htm":
            return FileTypeFilter(label: "html", extensions: ["html", "htm"], contentTypes: ["public.html"])
        case "image", "img", "图片":
            return FileTypeFilter(label: "image", extensions: ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff"], contentTypes: ["public.image"])
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            return FileTypeFilter(label: raw.lowercased(), extensions: [raw.lowercased()], contentTypes: ["public.image"])
        case "zip", "rar", "7z", "archive":
            return FileTypeFilter(label: "zip", extensions: ["zip", "rar", "7z", "tar", "gz"], contentTypes: ["public.zip-archive", "public.archive"])
        case "swift", "py", "js", "ts", "java", "go", "rs", "c", "cpp", "h", "m", "mm":
            return FileTypeFilter(label: raw.lowercased(), extensions: [raw.lowercased()], contentTypes: ["public.source-code"])
        default:
            return nil
        }
    }
}

@MainActor
final class SpotlightFileSearcher {
    private var workTask: Task<Void, Never>?
    private let processBox = MdfindProcessBox()

    func stop() {
        workTask?.cancel()
        workTask = nil
        processBox.killCurrent()
    }

    func search(
        parsed: ParsedFileSearchQuery,
        scope: FileSearchScope,
        extraFolders: [URL],
        limit: Int,
        timeout: TimeInterval,
        completion: @escaping ([FileSearchHit], Bool) -> Void
    ) {
        stop()
        let folderPaths = extraFolders.map(\.path)
        let box = processBox
        workTask = Task.detached(priority: .userInitiated) {
            let started = Date()
            let deadline = started.addingTimeInterval(timeout)
            let paths = MdfindCLI.search(
                parsed: parsed,
                scope: scope,
                folders: folderPaths,
                limit: limit,
                deadline: deadline,
                processBox: box
            )
            let timedOut = Date() >= deadline || Task.isCancelled
            var hits: [FileSearchHit] = []
            hits.reserveCapacity(min(paths.count, limit))
            for (index, path) in paths.enumerated() {
                if Task.isCancelled { break }
                // Skip trailing slash directories without a full filesystem stat.
                if path.hasSuffix("/") { continue }
                let url = URL(fileURLWithPath: path, isDirectory: false)
                let name = url.lastPathComponent
                guard !name.isEmpty, !name.hasPrefix(".") else { continue }
                let directory = FileSearchEngine.displayDirectory(for: url)
                if !FileSearchEngine.matches(url: url, name: name, parsed: parsed) {
                    continue
                }
                let score = FileNameRanker.score(
                    name: name,
                    path: directory,
                    parsed: parsed
                ) ?? (400 - index)
                hits.append(
                    FileSearchHit(
                        id: path,
                        url: url,
                        name: name,
                        directory: directory,
                        score: 600 + score,
                        source: scope
                    )
                )
            }
            let sorted = hits.sorted { $0.score > $1.score }
            await MainActor.run {
                guard !Task.isCancelled else { return }
                completion(sorted, timedOut)
            }
        }
    }
}

/// Tracks the live `mdfind` pid so a newer query can kill the old one.
final class MdfindProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t = 0

    func set(_ value: pid_t) {
        lock.lock()
        pid = value
        lock.unlock()
    }

    func clear(_ value: pid_t) {
        lock.lock()
        if pid == value { pid = 0 }
        lock.unlock()
    }

    func killCurrent() {
        lock.lock()
        let current = pid
        pid = 0
        lock.unlock()
        if current > 0 {
            kill(current, SIGTERM)
        }
    }
}

enum MdfindCLI {
    static func search(
        parsed: ParsedFileSearchQuery,
        scope: FileSearchScope,
        folders: [String],
        limit: Int,
        deadline: Date,
        processBox: MdfindProcessBox? = nil
    ) -> [String] {
        guard !parsed.isEmpty else { return [] }

        var clauses: [String] = []

        // Type filters are OR within the group, AND against name tokens.
        // Extension-only predicates are much faster than ContentTypeTree ORs.
        if !parsed.typeFilters.isEmpty {
            let typeParts = parsed.typeFilters.flatMap { filter -> [String] in
                filter.extensions.map { ext in
                    let e = escapeSpotlightLiteral(ext)
                    return "kMDItemFSName == \"*.\(e)\"cdw"
                }
            }
            if !typeParts.isEmpty {
                clauses.append("(\(typeParts.joined(separator: " || ")))")
            }
        }

        for token in parsed.nameTokens {
            let cleaned = token.replacingOccurrences(of: "*", with: "")
            guard !cleaned.isEmpty else { continue }
            let escaped = escapeSpotlightLiteral(cleaned)
            // DisplayName only — FSName duplicate doubles Spotlight work.
            // Fuzzy ranking stays client-side.
            if parsed.searchContents {
                clauses.append(
                    "(kMDItemDisplayName == \"*\(escaped)*\"cdw || kMDItemTextContent == \"*\(escaped)*\"cdw)"
                )
            } else {
                clauses.append("kMDItemDisplayName == \"*\(escaped)*\"cdw")
            }
        }

        guard !clauses.isEmpty else { return [] }
        let predicate =
            "((kMDItemSupportFileType != \"MDSystemFile\") && (\(clauses.joined(separator: " && "))))"

        // Prefer Home first even for "整台 Mac" — paints results fast, then
        // a short whole-disk pass fills remaining slots (Raycast-like feel).
        let onlyIn: [String?]
        switch scope {
        case .thisMac, .authorized:
            onlyIn = [NSHomeDirectory(), nil]
        case .home:
            onlyIn = [NSHomeDirectory()]
        case .recent:
            return []
        }

        var paths: [String] = []
        var seen = Set<String>()
        for folder in onlyIn {
            if paths.count >= limit || Task.isCancelled || Date() >= deadline { break }
            var args = ["/usr/bin/mdfind", "-0"]
            if let folder, !folder.isEmpty {
                args += ["-onlyin", folder]
            }
            args.append(predicate)
            let remaining = limit - paths.count
            let chunk = posixSpawnCapturePaths(
                executable: "/usr/bin/mdfind",
                arguments: args,
                limit: remaining,
                deadline: deadline,
                processBox: processBox
            )
            for path in chunk {
                if paths.count >= limit { break }
                guard !path.isEmpty, seen.insert(path).inserted else { continue }
                paths.append(path)
            }
        }
        _ = folders // reserved for future custom scopes
        return paths
    }

    private static func escapeSpotlightLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Streams null-separated paths and SIGTERM's mdfind as soon as we have
    /// enough hits or the deadline passes — avoids waiting for full-disk drain.
    private static func posixSpawnCapturePaths(
        executable: String,
        arguments: [String],
        limit: Int,
        deadline: Date,
        processBox: MdfindProcessBox?
    ) -> [String] {
        guard limit > 0 else { return [] }

        var outputPipe: [Int32] = [0, 0]
        guard pipe(&outputPipe) == 0 else { return [] }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, outputPipe[1])
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        let argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }

        var pid: pid_t = 0
        let spawnResult = argv.withUnsafeBufferPointer { ptr in
            posix_spawn(&pid, executable, &fileActions, nil, ptr.baseAddress, environ)
        }
        close(outputPipe[1])
        guard spawnResult == 0 else {
            close(outputPipe[0])
            return []
        }
        processBox?.set(pid)

        var paths: [String] = []
        var pending = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while paths.count < limit {
            if Task.isCancelled || Date() >= deadline {
                kill(pid, SIGTERM)
                break
            }
            let count = read(outputPipe[0], &buffer, buffer.count)
            if count <= 0 { break }
            pending.append(contentsOf: buffer.prefix(count))
            while let nul = pending.firstIndex(of: 0) {
                let slice = pending[..<nul]
                pending.removeSubrange(...nul)
                if let path = String(data: Data(slice), encoding: .utf8), !path.isEmpty {
                    paths.append(path)
                    if paths.count >= limit {
                        kill(pid, SIGTERM)
                        break
                    }
                }
            }
        }
        close(outputPipe[0])
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        processBox?.clear(pid)
        return paths
    }
}

enum FileSearchEngine {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    static func localHits(
        parsed: ParsedFileSearchQuery,
        scope: FileSearchScope,
        openURLs: [URL],
        recent: [URL],
        workspaceFiles: [URL]
    ) -> [FileSearchHit] {
        var hits: [FileSearchHit] = []
        var seen = Set<String>()

        func append(_ url: URL, source: FileSearchScope, base: Int) {
            let path = url.path
            guard seen.insert(path).inserted else { return }
            let name = url.lastPathComponent
            let directory = displayDirectory(for: url)
            guard matches(url: url, name: name, parsed: parsed) else { return }
            let score: Int
            if parsed.isEmpty {
                score = base
            } else if let ranked = FileNameRanker.score(name: name, path: directory, parsed: parsed) {
                score = base + ranked
            } else {
                return
            }
            hits.append(
                FileSearchHit(
                    id: path,
                    url: url,
                    name: name,
                    directory: directory,
                    score: score,
                    source: source
                )
            )
        }

        openURLs.forEach { append($0, source: .recent, base: 1_000) }
        recent.forEach { append($0, source: .recent, base: 900) }
        if scope != .recent {
            for url in workspaceFiles.prefix(400) {
                append(url, source: .authorized, base: 700)
            }
        }
        return hits.sorted { $0.score > $1.score }
    }

    static func matches(url: URL, name: String, parsed: ParsedFileSearchQuery) -> Bool {
        if !parsed.typeFilters.isEmpty {
            let ext = url.pathExtension.lowercased()
            let typeOK = parsed.typeFilters.contains { filter in
                filter.extensions.contains(ext)
            }
            if !typeOK { return false }
        }
        if parsed.nameTokens.isEmpty { return true }
        return FileNameRanker.score(name: name, path: url.path, parsed: parsed) != nil
    }

    static func merge(local: [FileSearchHit], deep: [FileSearchHit], limit: Int) -> [FileSearchHit] {
        var seen = Set<String>()
        var merged: [FileSearchHit] = []
        for hit in (local + deep).sorted(by: { $0.score > $1.score }) {
            if seen.insert(hit.id).inserted {
                merged.append(hit)
            }
            if merged.count >= limit { break }
        }
        return merged
    }

    static func displayDirectory(for url: URL) -> String {
        url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    struct PreviewBundle {
        let metadata: FileSearchController.FileSearchMetadata
        let text: String
        let image: UIImage?
    }

    /// Raycast-style preview: QuickLook thumbnail for Office/PDF/images, text
    /// snippet for source/markdown. Metadata always filled.
    static func previewBundle(for url: URL) async -> PreviewBundle {
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }

        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ])
        let size = values?.fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? "—"
        let created = values?.creationDate.map { dateFormatter.string(from: $0) } ?? "—"
        let modified = values?.contentModificationDate.map { dateFormatter.string(from: $0) } ?? "—"
        let typeName = values?.localizedTypeDescription ?? url.pathExtension.uppercased()
        let meta = FileSearchController.FileSearchMetadata(
            name: url.lastPathComponent,
            wherePath: displayDirectory(for: url),
            typeName: typeName.isEmpty ? "文件" : typeName,
            size: size,
            created: created,
            modified: modified
        )

        let ext = url.pathExtension.lowercased()
        let textLike: Set<String> = [
            "txt", "md", "markdown", "swift", "py", "js", "ts", "json", "jsonc",
            "xml", "plist", "yml", "yaml", "toml", "csv", "log", "html", "htm",
            "css", "c", "cpp", "h", "m", "mm", "go", "rs", "java", "sh", "zsh"
        ]

        if let image = loadImagePreview(url: url, extension: ext) {
            return PreviewBundle(metadata: meta, text: "", image: image)
        }

        // Mid-size QL thumbs are enough for the pane and much cheaper than 900pt.
        if let thumb = await quickLookThumbnail(url: url, pixelSize: CGSize(width: 640, height: 480)) {
            return PreviewBundle(metadata: meta, text: "", image: thumb)
        }

        var text = ""
        if textLike.contains(ext) || ext.isEmpty {
            if let handle = try? FileHandle(forReadingFrom: url) {
                defer { try? handle.close() }
                let data = handle.readData(ofLength: 12_288)
                if let decoded = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1) {
                    let sample = decoded.prefix(512)
                    let control = sample.unicodeScalars.filter {
                        $0.value < 9 || ($0.value > 13 && $0.value < 32)
                    }.count
                    if control < 8 { text = decoded }
                }
            }
        }
        if text.isEmpty {
            text = "（无预览缩略图，可直接打开文件）"
        }
        return PreviewBundle(metadata: meta, text: text, image: nil)
    }

    private static func loadImagePreview(url: URL, extension ext: String) -> UIImage? {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
        guard imageExts.contains(ext) else { return nil }
        // Prefer ImageIO downsampled thumb — avoid decoding full-res into RAM.
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 720,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary
           ) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(contentsOfFile: url.path)
    }

    private static func quickLookThumbnail(url: URL, pixelSize: CGSize) async -> UIImage? {
        #if canImport(QuickLookThumbnailing)
        let scale = await MainActor.run { () -> CGFloat in
            #if canImport(UIKit)
            UIScreen.main.scale
            #else
            2.0
            #endif
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: pixelSize,
            scale: scale,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.uiImage)
            }
        }
        #else
        return nil
        #endif
    }
}

enum FileNameRanker {
    static func score(name: String, path: String, parsed: ParsedFileSearchQuery) -> Int? {
        score(name: name, path: path, tokens: parsed.nameTokens)
    }

    /// Every name token must hit (AND). Fuzzy subsequence allowed.
    static func score(name: String, path: String, tokens: [String]) -> Int? {
        if tokens.isEmpty { return 0 }
        let hayName = name.lowercased()
        let hayPath = path.lowercased()
        var total = 0
        for token in tokens {
            let needle = token.lowercased()
            if hayName == needle {
                total += 10_000
            } else if hayName.hasPrefix(needle) {
                total += 8_000 + max(0, 40 - hayName.count)
            } else if let range = hayName.range(of: needle) {
                let index = hayName.distance(from: hayName.startIndex, to: range.lowerBound)
                total += 5_000 - index
            } else if fuzzyMatch(hayName, needle) {
                total += 2_500
            } else if hayPath.contains(needle) {
                total += 1_000
            } else {
                return nil
            }
        }
        return total
    }

    private static func fuzzyMatch(_ haystack: String, _ needle: String) -> Bool {
        var hay = haystack.startIndex
        for ch in needle {
            guard let found = haystack[hay...].firstIndex(of: ch) else { return false }
            hay = haystack.index(after: found)
        }
        return true
    }
}

struct FileSearchView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences
    let dismiss: () -> Void
    /// When embedded in the floating panel, omit the outer min-size so the
    /// panel chrome owns sizing/dragging.
    var fillsAvailableSpace: Bool = false
    @StateObject private var controller = FileSearchController()
    @FocusState private var queryFocused: Bool

    private let quickTypes = ["pdf", "excel", "word", "ppt", "txt", "md", "image", "zip"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    preferences.tr("搜索文件…", "Search files…"),
                    text: $controller.query
                )
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
                    .onSubmit { openSelected() }
                    .onChange(of: controller.query) { _, _ in controller.scheduleSearch() }
                Picker("", selection: $controller.scope) {
                    ForEach(FileSearchController.pickerScopes) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .onChange(of: controller.scope) { _, _ in controller.scheduleSearch() }

                if controller.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help(preferences.tr("关闭", "Close"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.bar)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickTypes, id: \.self) { type in
                        let active = controller.query
                            .split(whereSeparator: \.isWhitespace)
                            .map { $0.lowercased() }
                            .contains(type)
                        Button(type) {
                            toggleTypeToken(type)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            active ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            Divider()

            HStack(spacing: 0) {
                resultsColumn
                    .frame(minWidth: 280, idealWidth: 340)
                    .frame(maxWidth: 420)
                Divider()
                previewColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Label(preferences.tr("搜索文件", "Search Files"), systemImage: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !controller.statusMessage.isEmpty {
                    Text(controller.statusMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(preferences.tr("打开", "Open"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⏎")
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .frame(
            minWidth: fillsAvailableSpace ? 0 : 900,
            minHeight: fillsAvailableSpace ? 0 : 540
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .onAppear {
            controller.attach(workspace: workspace)
            queryFocused = true
        }
        .onDisappear {
            controller.stop()
        }
    }

    private func toggleTypeToken(_ type: String) {
        var tokens = controller.query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        if let index = tokens.firstIndex(where: { $0.lowercased() == type }) {
            tokens.remove(at: index)
        } else {
            tokens.append(type)
        }
        controller.query = tokens.joined(separator: " ")
        controller.scheduleSearch()
    }

    private var resultsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(preferences.tr("文件", "Files"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            if controller.results.isEmpty {
                ContentUnavailableView(
                    preferences.tr("没有匹配文件", "No Matching Files"),
                    systemImage: "doc.magnifyingglass",
                    description: Text(emptyDescription)
                )
            } else {
                List(controller.results, selection: Binding(
                    get: { controller.selectedID },
                    set: { if let id = $0 { controller.select(id) } }
                )) { hit in
                    HStack(spacing: 10) {
                        Image(systemName: iconName(for: hit.url))
                            .foregroundStyle(.tint)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hit.name)
                                .lineLimit(1)
                            Text(hit.directory)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .tag(hit.id)
                    .contentShape(Rectangle())
                    .onTapGesture { controller.select(hit.id) }
                    .onTapGesture(count: 2) {
                        controller.select(hit.id)
                        openSelected()
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyDescription: String {
        preferences.tr(
            "支持：空格多词（全部匹配）、模糊匹配、类型词（pdf excel word ppt txt md image zip）。例：天山 周报 pdf",
            "Supports space-separated terms (AND), fuzzy match, and type words (pdf excel word ppt…). Example: report draft pdf"
        )
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if let image = controller.previewImage {
                    ScrollView {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(10)
                    }
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else if !controller.previewText.isEmpty {
                    ScrollView {
                        Text(controller.previewText)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ContentUnavailableView(
                        preferences.tr("选择文件以预览", "Select a File to Preview"),
                        systemImage: "doc.text.magnifyingglass"
                    )
                }
            }
            .frame(maxHeight: .infinity)

            if let meta = controller.metadata {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    metaRow(preferences.tr("名称", "Name"), meta.name)
                    metaRow(preferences.tr("位置", "Where"), meta.wherePath)
                    metaRow(preferences.tr("类型", "Type"), meta.typeName)
                    metaRow(preferences.tr("大小", "Size"), meta.size)
                    metaRow(preferences.tr("创建", "Created"), meta.created)
                    metaRow(preferences.tr("修改", "Modified"), meta.modified)
                }
                .padding(.bottom, 4)
            }

            HStack {
                Spacer()
                Button(preferences.tr("打开", "Open")) { openSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.selectedHit() == nil)
            }
        }
        .padding(14)
    }

    private func metaRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func iconName(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "swift", "m", "mm", "h", "c", "cpp", "js", "ts", "py", "java": return "chevron.left.forwardslash.chevron.right"
        case "json", "jsonc", "plist", "yml", "yaml", "toml": return "curlybraces"
        case "md", "txt", "log": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "webp": return "photo"
        case "pdf": return "doc.richtext"
        default: return "doc"
        }
    }

    private func openSelected() {
        guard let hit = controller.selectedHit() else { return }
        // Always use the system default app (Excel / Word / Preview…).
        // NotepadPlus is a text editor and must not hijack office/binary files.
        _ = SystemSnippetBridge.openWithDefaultApplication(hit.url)
        dismiss()
    }
}

/// Draggable + resizable floating chrome (Catalyst sheets are modal/fixed).
/// Uses topLeading + offset (not `.position`) and `compositingGroup` so drag
/// does not leave a ghost/shadow trail.
struct FloatingPanelHost<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    var showsScrim: Bool = true
    var initialSize: CGSize = CGSize(width: 960, height: 620)
    @ViewBuilder var content: () -> Content

    @State private var panelSize: CGSize
    @State private var panelOrigin = CGPoint(x: 80, y: 72)
    @State private var dragStartOrigin: CGPoint?
    @State private var resizeStartSize: CGSize?
    @State private var isInteracting = false

    private let minSize = CGSize(width: 640, height: 420)
    private let maxSize = CGSize(width: 1800, height: 1200)

    init(
        isPresented: Binding<Bool>,
        title: String,
        showsScrim: Bool = true,
        initialSize: CGSize = CGSize(width: 960, height: 620),
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isPresented = isPresented
        self.title = title
        self.showsScrim = showsScrim
        self.initialSize = initialSize
        self.content = content
        _panelSize = State(initialValue: initialSize)
    }

    var body: some View {
        GeometryReader { geo in
            let origin = clampedOrigin(in: geo.size)
            ZStack(alignment: .topLeading) {
                if showsScrim {
                    Color.black.opacity(0.14)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                }

                panel(in: geo.size)
                    .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
                    .offset(x: origin.x, y: origin.y)
            }
        }
        .transition(.opacity)
        .animation(nil, value: panelOrigin)
        .animation(nil, value: panelSize)
    }

    private func panel(in container: CGSize) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.headline)
                    Spacer(minLength: 0)
                    Text("拖动标题栏 · 右下角缩放")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isInteracting = true
                            if dragStartOrigin == nil { dragStartOrigin = panelOrigin }
                            guard let start = dragStartOrigin else { return }
                            panelOrigin = CGPoint(
                                x: start.x + value.translation.width,
                                y: start.y + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            dragStartOrigin = nil
                            panelOrigin = clampedOrigin(in: container)
                            isInteracting = false
                        }
                )

                Divider()
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.22), lineWidth: 1)
            )
            // Flatten layer before shadow — prevents the drag "ghost" trail.
            .compositingGroup()
            .shadow(
                color: .black.opacity(isInteracting ? 0.10 : 0.18),
                radius: isInteracting ? 6 : 14,
                y: isInteracting ? 3 : 8
            )

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(10)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            isInteracting = true
                            if resizeStartSize == nil { resizeStartSize = panelSize }
                            guard let start = resizeStartSize else { return }
                            let width = min(max(start.width + value.translation.width, minSize.width), maxSize.width)
                            let height = min(max(start.height + value.translation.height, minSize.height), maxSize.height)
                            panelSize = CGSize(width: width, height: height)
                        }
                        .onEnded { _ in
                            resizeStartSize = nil
                            panelOrigin = clampedOrigin(in: container)
                            isInteracting = false
                        }
                )
        }
    }

    private func clampedOrigin(in container: CGSize) -> CGPoint {
        let maxX = max(12, container.width - panelSize.width - 12)
        let maxY = max(12, container.height - panelSize.height - 12)
        return CGPoint(
            x: min(max(12, panelOrigin.x), maxX),
            y: min(max(12, panelOrigin.y), maxY)
        )
    }
}

// MARK: - Snippets (Search + Create, Raycast-style)

enum SnippetOrganization: String, CaseIterable, Codable, Identifiable {
    case personal
    case work
    case shared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal"
        case .work: "Work"
        case .shared: "Shared"
        }
    }
}

enum SnippetListFilter: String, CaseIterable, Identifiable {
    case all
    case personal
    case work
    case shared

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .personal: "Personal"
        case .work: "Work"
        case .shared: "Shared"
        }
    }
}

struct TextSnippet: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var body: String
    var shortcut: String
    var organization: SnippetOrganization
    var createdAt: Date
    var updatedAt: Date
    var timesCopied: Int
    var lastCopiedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        shortcut: String = "",
        organization: SnippetOrganization = .personal,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        timesCopied: Int = 0,
        lastCopiedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.shortcut = shortcut
        self.organization = organization
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.timesCopied = timesCopied
        self.lastCopiedAt = lastCopiedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, shortcut, organization, createdAt, updatedAt, timesCopied, lastCopiedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut) ?? ""
        organization = try container.decodeIfPresent(SnippetOrganization.self, forKey: .organization) ?? .personal
        let legacyUpdated = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? legacyUpdated
        updatedAt = legacyUpdated
        timesCopied = try container.decodeIfPresent(Int.self, forKey: .timesCopied) ?? 0
        lastCopiedAt = try container.decodeIfPresent(Date.self, forKey: .lastCopiedAt)
    }
}

enum SnippetPlaceholder {
    static func expand(_ template: String) -> String {
        var text = template
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .medium
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateStyle = .medium
        dateTimeFormatter.timeStyle = .medium

        let replacements: [String: String] = [
            "{clipboard}": UIPasteboard.general.string ?? "",
            "{date}": dateFormatter.string(from: now),
            "{time}": timeFormatter.string(from: now),
            "{datetime}": dateTimeFormatter.string(from: now),
            "{iso8601}": ISO8601DateFormatter().string(from: now)
        ]
        for (token, value) in replacements {
            text = text.replacingOccurrences(of: token, with: value)
        }
        return text
    }
}

@MainActor
final class SnippetStore: ObservableObject {
    static let shared = SnippetStore()

    @Published private(set) var snippets: [TextSnippet] = []
    private let key = "notepad-plus.snippets.v2"

    private init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([TextSnippet].self, from: data) {
            snippets = decoded.sorted { $0.updatedAt > $1.updatedAt }
            return
        }
        // Migrate v1 payloads that only had title/body/shortcut/updatedAt.
        if let legacy = UserDefaults.standard.data(forKey: "notepad-plus.snippets.v1"),
           let decoded = try? JSONDecoder().decode([TextSnippet].self, from: legacy) {
            snippets = decoded.sorted { $0.updatedAt > $1.updatedAt }
            save()
            return
        }
        if snippets.isEmpty {
            snippets = [
                TextSnippet(title: "TODO", body: "// TODO: ", shortcut: "todo"),
                TextSnippet(title: "当前日期", body: "{date}", shortcut: "date"),
                TextSnippet(title: "剪贴板内容", body: "{clipboard}", shortcut: "clip")
            ]
            save()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ snippet: TextSnippet) {
        var item = snippet
        item.updatedAt = Date()
        if let index = snippets.firstIndex(where: { $0.id == item.id }) {
            snippets[index] = item
        } else {
            snippets.insert(item, at: 0)
        }
        snippets.sort { $0.updatedAt > $1.updatedAt }
        save()
    }

    func remove(_ id: UUID) {
        snippets.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func markUsed(_ id: UUID) -> TextSnippet? {
        guard let index = snippets.firstIndex(where: { $0.id == id }) else { return nil }
        snippets[index].timesCopied += 1
        snippets[index].lastCopiedAt = Date()
        snippets[index].updatedAt = Date()
        let item = snippets[index]
        snippets.sort { $0.updatedAt > $1.updatedAt }
        save()
        return item
    }
}

private enum SnippetRecencySection: String, CaseIterable, Identifiable {
    case thisWeek
    case thisYear
    case older

    var id: String { rawValue }

    func title(preferences: EditorPreferences) -> String {
        switch self {
        case .thisWeek: preferences.tr("本周", "This Week")
        case .thisYear: preferences.tr("今年", "This Year")
        case .older: preferences.tr("更早", "Older")
        }
    }

    static func section(for date: Date, now: Date = Date()) -> SnippetRecencySection {
        let calendar = Calendar.current
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return .thisWeek
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return .thisYear
        }
        return .older
    }
}

enum SnippetsEntryMode {
    case search
    case create
}

struct SnippetsView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences
    var initialMode: SnippetsEntryMode = .search
    var fillsAvailableSpace: Bool = false
    let dismiss: () -> Void

    @ObservedObject private var store = SnippetStore.shared
    @State private var mode: SnippetsEntryMode = .search
    @State private var query = ""
    @State private var listFilter: SnippetListFilter = .all
    @State private var selectedID: UUID?
    @State private var showActions = false

    // Create form
    @State private var draftOrganization: SnippetOrganization = .personal
    @State private var draftName = ""
    @State private var draftBody = ""
    @State private var editingID: UUID?

    @FocusState private var searchFocused: Bool
    @FocusState private var createNameFocused: Bool

    var body: some View {
        Group {
            switch mode {
            case .search:
                searchSnippetsChrome
            case .create:
                createSnippetChrome
            }
        }
        .frame(
            minWidth: fillsAvailableSpace ? 0 : 880,
            minHeight: fillsAvailableSpace ? 0 : 540
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            mode = initialMode
            if selectedID == nil {
                selectedID = filteredSnippets.first?.id
            }
            if mode == .search {
                searchFocused = true
            } else {
                createNameFocused = true
            }
        }
    }

    // MARK: Search

    private var searchSnippetsChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(preferences.tr("搜索代码片段…", "Search snippets…"), text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit { pasteSelected() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Menu {
                    ForEach(SnippetListFilter.allCases) { filter in
                        Button(filter.title) { listFilter = filter }
                    }
                } label: {
                    Label(listFilter.title, systemImage: "line.3.horizontal.decrease")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 0) {
                searchListColumn
                    .frame(width: 300)
                Divider()
                searchDetailColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack(spacing: 12) {
                Label(preferences.tr("搜索代码片段", "Search Snippets"), systemImage: "doc.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(preferences.tr("全局 ⌥⌘S · 粘贴回原光标", "Global ⌥⌘S · paste at prior caret"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                Button {
                    pasteSelected()
                } label: {
                    HStack(spacing: 8) {
                        Text(preferences.tr("粘贴到光标处", "Paste at Caret"))
                        Text("⏎")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSnippet == nil)
                .keyboardShortcut(.defaultAction)

                Menu {
                    Button(preferences.tr("新建代码片段…", "Create Snippet…")) {
                        beginCreate()
                    }
                    Button(preferences.tr("复制内容", "Copy Content")) {
                        copySelected()
                    }
                    .disabled(selectedSnippet == nil)
                    Button(preferences.tr("编辑…", "Edit…")) {
                        beginEditSelected()
                    }
                    .disabled(selectedSnippet == nil)
                    Divider()
                    Button(preferences.tr("删除", "Delete"), role: .destructive) {
                        deleteSelected()
                    }
                    .disabled(selectedSnippet == nil)
                } label: {
                    HStack(spacing: 6) {
                        Text(preferences.tr("操作", "Actions"))
                        Text("⌘K")
                            .font(.caption.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var searchListColumn: some View {
        Group {
            if groupedSnippets.isEmpty {
                ContentUnavailableView(
                    preferences.tr("没有代码片段", "No Snippets"),
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(preferences.tr("创建一个片段，或调整筛选条件。", "Create a snippet or adjust the filter."))
                )
            } else {
                List(selection: $selectedID) {
                    ForEach(groupedSnippets, id: \.section) { group in
                        Section(group.section.title(preferences: preferences)) {
                            ForEach(group.items) { snippet in
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 18)
                                    Text(snippet.title)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .tag(snippet.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedID = snippet.id }
                                .onTapGesture(count: 2) {
                                    selectedID = snippet.id
                                    pasteSelected()
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var searchDetailColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let snippet = selectedSnippet {
                ScrollView {
                    Text(snippet.body)
                        .font(.system(.title3, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(16)
                }
                .frame(maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(preferences.tr("信息", "Information"))
                        .font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        infoRow(preferences.tr("名称", "Name"), snippet.title)
                        infoRow(preferences.tr("内容类型", "Content type"), preferences.tr("文本", "Text"))
                        infoRow(preferences.tr("所属", "Organization"), snippet.organization.title)
                        infoRow(preferences.tr("复制次数", "Times copied"), "\(snippet.timesCopied)")
                        infoRow(
                            preferences.tr("最近复制", "Last copied"),
                            snippet.lastCopiedAt.map(absoluteTime) ?? preferences.tr("从未", "Never")
                        )
                    }
                }
            } else {
                ContentUnavailableView(
                    preferences.tr("选择一个代码片段", "Select a Snippet"),
                    systemImage: "doc.text"
                )
            }
        }
        .padding(16)
    }

    // MARK: Create

    private var createSnippetChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    mode = .search
                    editingID = nil
                    searchFocused = true
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                Text(preferences.tr(
                    "可使用 {clipboard}、{date}、{time}、{datetime}、{iso8601} 作为动态占位符。",
                    "Use {clipboard}, {date}, {time}, {datetime}, {iso8601} as dynamic placeholders."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    labeledField(preferences.tr("组织", "Organization")) {
                        Picker("", selection: $draftOrganization) {
                            ForEach(SnippetOrganization.allCases) { org in
                                Text(org.title).tag(org)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    labeledField(preferences.tr("名称", "Name")) {
                        TextField(preferences.tr("片段名称", "Snippet name"), text: $draftName)
                            .textFieldStyle(.plain)
                            .focused($createNameFocused)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    labeledField(preferences.tr("片段内容", "Snippet")) {
                        ZStack(alignment: .topLeading) {
                            if draftBody.isEmpty {
                                Text(preferences.tr("在这里写下你的片段…", "Find your inner Shakespeare…"))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                            }
                            TextEditor(text: $draftBody)
                                .font(.system(.body, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 220)
                                .padding(8)
                        }
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Text(preferences.tr(
                        "可加入 {Dynamic Placeholders}，例如复制文本或当前日期。",
                        "Include {Dynamic Placeholders} for context like the copied text or the current date."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 20)
            }

            Divider()
            HStack {
                Label(
                    editingID == nil
                        ? preferences.tr("新建代码片段", "Create Snippet")
                        : preferences.tr("编辑代码片段", "Edit Snippet"),
                    systemImage: "doc.badge.plus"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    saveDraft()
                } label: {
                    HStack(spacing: 8) {
                        Text(preferences.tr("保存片段", "Save Snippet"))
                        HStack(spacing: 3) {
                            Text("⌘")
                            Text("⏎")
                        }
                        .font(.caption.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .background(Color(uiColor: .systemBackground))
    }

    // MARK: Data helpers

    private var filteredSnippets: [TextSnippet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.snippets.filter { snippet in
            switch listFilter {
            case .all: break
            case .personal: if snippet.organization != .personal { return false }
            case .work: if snippet.organization != .work { return false }
            case .shared: if snippet.organization != .shared { return false }
            }
            guard !q.isEmpty else { return true }
            return snippet.title.localizedCaseInsensitiveContains(q)
                || snippet.body.localizedCaseInsensitiveContains(q)
                || snippet.shortcut.localizedCaseInsensitiveContains(q)
        }
    }

    private var groupedSnippets: [(section: SnippetRecencySection, items: [TextSnippet])] {
        let grouped = Dictionary(grouping: filteredSnippets) {
            SnippetRecencySection.section(for: $0.lastCopiedAt ?? $0.updatedAt)
        }
        return SnippetRecencySection.allCases.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }

    private var selectedSnippet: TextSnippet? {
        filteredSnippets.first(where: { $0.id == selectedID }) ?? filteredSnippets.first
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func absoluteTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func beginCreate() {
        editingID = nil
        draftOrganization = .personal
        draftName = ""
        draftBody = ""
        mode = .create
        createNameFocused = true
    }

    private func beginEditSelected() {
        guard let snippet = selectedSnippet else { return }
        editingID = snippet.id
        draftOrganization = snippet.organization
        draftName = snippet.title
        draftBody = snippet.body
        mode = .create
        createNameFocused = true
    }

    private func saveDraft() {
        let title = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let snippet = TextSnippet(
            id: editingID ?? UUID(),
            title: title,
            body: draftBody,
            organization: draftOrganization,
            createdAt: store.snippets.first(where: { $0.id == editingID })?.createdAt ?? Date(),
            timesCopied: store.snippets.first(where: { $0.id == editingID })?.timesCopied ?? 0,
            lastCopiedAt: store.snippets.first(where: { $0.id == editingID })?.lastCopiedAt
        )
        store.upsert(snippet)
        selectedID = snippet.id
        editingID = nil
        mode = .search
        searchFocused = true
    }

    private func expandedBody(for snippet: TextSnippet) -> String {
        SnippetPlaceholder.expand(snippet.body)
    }

    private func pasteSelected() {
        guard let snippet = selectedSnippet else { return }
        let text = expandedBody(for: snippet)
        store.markUsed(snippet.id)
        ClipboardHistoryStore.shared.record(text)
        dismiss()
        Task { @MainActor in
            await pasteTextEverywhere(text, workspace: workspace)
        }
    }

    private func copySelected() {
        guard let snippet = selectedSnippet else { return }
        let text = expandedBody(for: snippet)
        store.markUsed(snippet.id)
        UIPasteboard.general.string = text
        ClipboardHistoryStore.shared.record(text)
    }

    private func deleteSelected() {
        guard let id = selectedSnippet?.id else { return }
        store.remove(id)
        selectedID = filteredSnippets.first?.id
    }
}

// MARK: - Clipboard History

struct ClipboardHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var createdAt: Date
    var lastUsedAt: Date
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        lastUsedAt: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.isPinned = isPinned
    }

    var previewLine: String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var characterCount: Int { (text as NSString).length }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    static let maxItems = 100
    static let maxStoredCharacters = 100_000

    @Published private(set) var items: [ClipboardHistoryItem] = []
    @Published var isMonitoringEnabled = true {
        didSet {
            UserDefaults.standard.set(isMonitoringEnabled, forKey: monitoringKey)
            if isMonitoringEnabled { startMonitoring() } else { stopMonitoring() }
        }
    }

    private let storageKey = "notepad-plus.clipboard-history.v1"
    private let monitoringKey = "notepad-plus.clipboard-history.monitoring.v1"
    private var pollTimer: Timer?
    private var lastChangeCount = -1
    private var suppressCaptureUntil: Date?
    private var pasteboardObserver: NSObjectProtocol?

    private init() {
        isMonitoringEnabled = UserDefaults.standard.object(forKey: monitoringKey) as? Bool ?? true
        load()
        if isMonitoringEnabled { startMonitoring() }
    }

    deinit {
        // Timers / observers are torn down explicitly from stopMonitoring on
        // the main actor; deinit cannot call @MainActor methods directly.
    }

    func startMonitoring() {
        guard pollTimer == nil else { return }
        lastChangeCount = UIPasteboard.general.changeCount
        // UIPasteboard.changedNotification is not always delivered for every
        // Catalyst pasteboard write, so poll changeCount as the source of truth.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfNeeded() }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
        pasteboardObserver = NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.captureIfNeeded() }
        }
        captureIfNeeded()
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let pasteboardObserver {
            NotificationCenter.default.removeObserver(pasteboardObserver)
            self.pasteboardObserver = nil
        }
    }

    func captureIfNeeded() {
        guard isMonitoringEnabled else { return }
        if let until = suppressCaptureUntil, until > Date() {
            lastChangeCount = UIPasteboard.general.changeCount
            return
        }
        let changeCount = UIPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        guard let text = UIPasteboard.general.string?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{0000}"))
        else { return }
        let trimmed = text
        guard !trimmed.isEmpty else { return }
        // Skip huge blobs so history stays responsive.
        guard (trimmed as NSString).length <= Self.maxStoredCharacters else { return }
        record(trimmed)
    }

    func record(_ text: String) {
        if let existing = items.firstIndex(where: { $0.text == text }) {
            var item = items.remove(at: existing)
            item.lastUsedAt = Date()
            items.insert(item, at: 0)
        } else {
            items.insert(ClipboardHistoryItem(text: text), at: 0)
        }
        // Keep pinned items even when trimming the tail.
        trimToLimit()
        save()
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        sortItems()
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.isPinned }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    /// Copy back to the system pasteboard and bump recency. Suppresses the
    /// subsequent pasteboard change so we do not duplicate the entry.
    func copyToPasteboard(_ item: ClipboardHistoryItem) {
        suppressCaptureUntil = Date().addingTimeInterval(1.0)
        UIPasteboard.general.string = item.text
        lastChangeCount = UIPasteboard.general.changeCount
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].lastUsedAt = Date()
            sortItems()
            save()
        }
    }

    private func trimToLimit() {
        if items.count <= Self.maxItems { return }
        var kept: [ClipboardHistoryItem] = []
        kept.reserveCapacity(Self.maxItems)
        let pinned = items.filter(\.isPinned)
        let unpinned = items.filter { !$0.isPinned }
        kept.append(contentsOf: pinned)
        let remaining = max(0, Self.maxItems - kept.count)
        kept.append(contentsOf: unpinned.prefix(remaining))
        items = kept
        sortItems()
    }

    private func sortItems() {
        items.sort { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            return lhs.lastUsedAt > rhs.lastUsedAt
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        else { return }
        items = decoded
        sortItems()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

struct ClipboardHistoryView: View {
    @ObservedObject var workspace: WorkspaceStore
    @ObservedObject var preferences: EditorPreferences
    var fillsAvailableSpace: Bool = false
    @ObservedObject private var store = ClipboardHistoryStore.shared
    let dismiss: () -> Void

    @State private var filter = ""
    @State private var selectedID: UUID?
    @FocusState private var filterFocused: Bool

    private var filtered: [ClipboardHistoryItem] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.items }
        return store.items.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    private var selectedItem: ClipboardHistoryItem? {
        filtered.first(where: { $0.id == selectedID }) ?? filtered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField(preferences.tr("筛选剪贴板…", "Filter clipboard…"), text: $filter)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onSubmit { pasteSelected() }
                Menu {
                    Toggle(
                        preferences.tr("监听系统剪贴板", "Watch System Clipboard"),
                        isOn: $store.isMonitoringEnabled
                    )
                    Divider()
                    Button(preferences.tr("清除未固定项", "Clear Unpinned"), role: .destructive) {
                        store.clearUnpinned()
                        selectedID = store.items.first?.id
                    }
                    Button(preferences.tr("清空全部", "Clear All"), role: .destructive) {
                        store.clearAll()
                        selectedID = nil
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                Button(preferences.tr("关闭", "Close")) { dismiss() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            HStack(spacing: 0) {
                listColumn
                    .frame(width: 340)
                Divider()
                detailColumn
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text(preferences.tr("粘贴回原光标（Raycast 同款）", "Paste at prior caret"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(preferences.tr("粘贴到光标处", "Paste at Caret")) { pasteSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedItem == nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(
            minWidth: fillsAvailableSpace ? 0 : 760,
            minHeight: fillsAvailableSpace ? 0 : 480
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            store.startMonitoring()
            store.captureIfNeeded()
            selectedID = filtered.first?.id
            filterFocused = true
        }
        .onChange(of: store.items) { _, items in
            if let selectedID, items.contains(where: { $0.id == selectedID }) { return }
            self.selectedID = filtered.first?.id
        }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                ContentUnavailableView(
                    preferences.tr("暂无历史", "No History"),
                    systemImage: "clipboard",
                    description: Text(preferences.tr(
                        "复制文本后会出现在这里。可固定常用项，避免被后续条目挤掉。",
                        "Copied text appears here. Pin important entries so they are not trimmed."
                    ))
                )
            } else {
                List(filtered, selection: $selectedID) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.isPinned ? "pin.fill" : "doc.on.clipboard")
                            .foregroundStyle(item.isPinned ? Color.orange : Color.accentColor)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.previewLine.isEmpty ? " " : item.previewLine)
                                .lineLimit(2)
                                .font(.body.monospaced())
                            Text(metaLine(for: item))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedID = item.id }
                    .onTapGesture(count: 2) {
                        selectedID = item.id
                        pasteSelected()
                    }
                    .contextMenu {
                        Button(preferences.tr("粘贴到光标处", "Paste at Caret")) {
                            selectedID = item.id
                            pasteSelected()
                        }
                        Button(preferences.tr("复制到剪贴板", "Copy to Clipboard")) {
                            store.copyToPasteboard(item)
                        }
                        Button(item.isPinned
                               ? preferences.tr("取消固定", "Unpin")
                               : preferences.tr("固定", "Pin")) {
                            store.togglePin(item.id)
                        }
                        Button(preferences.tr("删除", "Delete"), role: .destructive) {
                            store.remove(item.id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var detailColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = selectedItem {
                ScrollView {
                    Text(item.text)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(preferences.tr(
                    "\(item.characterCount) 字符 · \(relativeTime(item.lastUsedAt))",
                    "\(item.characterCount) characters · \(relativeTime(item.lastUsedAt))"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button {
                        store.togglePin(item.id)
                    } label: {
                        Label(
                            item.isPinned
                                ? preferences.tr("取消固定", "Unpin")
                                : preferences.tr("固定", "Pin"),
                            systemImage: item.isPinned ? "pin.slash" : "pin"
                        )
                    }
                    Button(role: .destructive) {
                        store.remove(item.id)
                    } label: {
                        Label(preferences.tr("删除", "Delete"), systemImage: "trash")
                    }
                    Spacer()
                    Button(preferences.tr("复制", "Copy")) {
                        store.copyToPasteboard(item)
                    }
                    Button(preferences.tr("粘贴到光标处", "Paste at Caret")) {
                        pasteSelected()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                ContentUnavailableView(
                    preferences.tr("选择一条历史", "Select an Entry"),
                    systemImage: "clipboard"
                )
            }
        }
        .padding(14)
    }

    private func metaLine(for item: ClipboardHistoryItem) -> String {
        let pin = item.isPinned ? preferences.tr("已固定 · ", "Pinned · ") : ""
        return pin + relativeTime(item.lastUsedAt) + " · " + "\(item.characterCount)"
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func pasteSelected() {
        guard let item = selectedItem else { return }
        store.copyToPasteboard(item)
        dismiss()
        Task { @MainActor in
            await pasteTextEverywhere(item.text, workspace: workspace)
        }
    }
}

/// Raycast DirectPaste: prefer the remembered external caret; only fall back
/// to the NotepadPlus editor when no other app was tracked.
@MainActor
func pasteTextEverywhere(_ text: String, workspace: WorkspaceStore) async {
    SystemSnippetBridge.promptAccessibilityIfNeeded()
    if !SystemSnippetBridge.pasteTargetIsSelf {
        await SystemSnippetBridge.pasteIntoPreviousApplication(text)
        return
    }
    if let document = workspace.activeDocument {
        let ns = document.content as NSString
        let range = document.selection
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        let updated = ns.replacingCharacters(in: safe, with: text)
        document.content = updated
        document.selection = NSRange(location: safe.location + (text as NSString).length, length: 0)
        workspace.documentDidChange(document)
        return
    }
    await SystemSnippetBridge.pasteIntoPreviousApplication(text)
}
