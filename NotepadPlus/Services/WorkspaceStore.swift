import Foundation
import SwiftUI

enum DocumentGroupColor: String, CaseIterable, Codable, Identifiable {
    case green, blue, purple, orange, red, pink, gray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .green: "翡翠绿"
        case .blue: "湖水蓝"
        case .purple: "薰衣草紫"
        case .orange: "暖橙"
        case .red: "珊瑚红"
        case .pink: "樱花粉"
        case .gray: "石墨灰"
        }
    }

    var color: Color {
        switch self {
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .orange: .orange
        case .red: .red
        case .pink: .pink
        case .gray: .gray
        }
    }
}

struct DocumentGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var color: DocumentGroupColor
    var parentID: UUID?

    init(id: UUID = UUID(), name: String, color: DocumentGroupColor = .green, parentID: UUID? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.parentID = parentID
    }

    private enum CodingKeys: String, CodingKey { case id, name, color, parentID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentID = try container.decodeIfPresent(UUID.self, forKey: .parentID)
        color = DocumentGroupColor(rawValue: try container.decodeIfPresent(String.self, forKey: .color) ?? "") ?? .green
    }
}

enum BottomPanelMode: String, CaseIterable, Identifiable {
    case search = "Find in Files"
    case functionList = "Function List"
    case bookmarks = "Bookmarks"
    case statistics = "Document Info"
    case jsonPath = "JSONPath"
    case jsonTree = "JSON Tree"
    case jsonTools = "JSON Tools"

    var id: String { rawValue }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case currentDocument
    case allOpenDocuments
    case workspaceFolder

    var id: String { rawValue }
}

struct WorkspaceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let fileURL: URL
    let documentID: UUID?
    let line: Int
    let column: Int
    let snippet: String
    let selection: NSRange
    let snippetMatches: [NSRange]

    init(
        fileURL: URL,
        documentID: UUID?,
        line: Int,
        column: Int,
        snippet: String,
        selection: NSRange,
        snippetMatches: [NSRange] = []
    ) {
        self.fileURL = fileURL
        self.documentID = documentID
        self.line = line
        self.column = column
        self.snippet = snippet
        self.selection = selection
        self.snippetMatches = snippetMatches
    }
}

struct SearchAllRequest {
    let query: String
    let options: SearchOptions
    let scope: SearchScope
    var range: NSRange? = nil
}

struct MarkAllRequest {
    let query: String
    let options: SearchOptions
    var range: NSRange? = nil
}

struct ExternalFileChange: Identifiable {
    let id: UUID
    let documentID: UUID
    let fileName: String
    let isDirty: Bool
}

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published private(set) var documents: [EditorDocument] = []
    @Published var activeDocumentID: UUID?
    @Published var isFindBarPresented = false
    let findReplaceState = FindReplaceState()

    func presentFindBar(replace: Bool = false) {
        findReplaceState.focusesReplacement = replace
        isFindBarPresented = true
        findReplaceState.focusRequest = UUID()
    }
    @Published var isMarkdownPreviewPresented = false
    @Published private(set) var recentFiles: [URL] = []
    @Published private(set) var workspaceFolder: URL?
    @Published private(set) var workspaceFiles: [URL] = []
    /// Folders the user previously authorized for sandbox access — used by
    /// Search File so queries stay fast and stay within reachable paths.
    @Published private(set) var authorizedFolders: [URL] = []
    /// File reads and text decoding are performed off the main actor so a
    /// large document cannot block the editor window while it is opening.
    private var loadingFileURLs: Set<URL> = []
    @Published private(set) var documentGroups: [DocumentGroup] = []
    @Published var selectedGroupID: UUID?
    @Published var isBottomPanelPresented = false
    @Published var bottomPanelMode: BottomPanelMode = .search
    @Published var workspaceSearchQuery = ""
    @Published var workspaceSearchReplacement = ""
    @Published var workspaceSearchOptions = SearchOptions()
    @Published var workspaceSearchScope: SearchScope = .allOpenDocuments
    @Published private(set) var workspaceSearchResults: [WorkspaceSearchResult] = []
    @Published var isSplitEditorPresented = false
    @Published var secondaryDocumentID: UUID?
    @Published var errorMessage: String?
    @Published var isFileAccessImporterPresented = false
    @Published var isFolderAccessImporterPresented = false
    private(set) var fileAccessRecoveryURL: URL?
    @Published var externalFileChange: ExternalFileChange?

    let preferences: EditorPreferences

    private var nextUntitledNumber = 1
    private var autosaveTasks: [UUID: Task<Void, Never>] = [:]
    private var recoveryPersistenceTasks: [UUID: Task<Void, Never>] = [:]
    private var sessionPersistenceTask: Task<Void, Never>?
    private var fileMonitorTimer: Timer?
    private var fileSignatures: [UUID: FileSignature] = [:]
    /// Extra changes waiting while an alert is already on screen. A single
    /// `@Published` slot would otherwise drop subsequent documents.
    private var pendingExternalFileChanges: [ExternalFileChange] = []
    /// After our own write, ignore mtime churn for a short window so autosave
    /// and “Save” do not immediately ask the user to reload their own file.
    private var suppressExternalChangeUntil: [UUID: Date] = [:]
    private var workspaceSecurityScopedURL: URL?
    private var documentSecurityScopedURLs: [UUID: URL] = [:]
    private var authorizedFolderURLs: [URL] = [] {
        didSet { authorizedFolders = authorizedFolderURLs }
    }
    private var authorizedFolderBookmarks: [String: Data] = [:]
    private var recentFileBookmarks: [String: Data] = [:]
    private var isSessionPersistenceBlocked = false
    private var lastSearchRevealKey: String?
    private var lastSearchRevealDate: Date?
    // Kept in memory so switching tabs restores the exact viewport without
    // publishing every scroll event through SwiftUI.
    private var documentScrollOffsets: [UUID: CGPoint] = [:]
    private let sessionKey = "notepad-plus.session.v1"
    private let recentKey = "notepad-plus.recent-files.v1"
    private let recentBookmarksKey = "notepad-plus.recent-bookmarks.v2"
    private let workspaceBookmarkKey = "notepad-plus.workspace-bookmark.v1"
    private let authorizedFoldersKey = "notepad-plus.authorized-folders.v1"
    private let sessionDefaults: UserDefaults
    private let recoveryRootURL: URL
    private lazy var scratchRecoveryStore = ScratchRecoveryStore(directoryURL: recoveryRootURL)
    private lazy var sessionArchive = WorkspaceSessionArchive(
        directoryURL: recoveryRootURL.deletingLastPathComponent()
            .appendingPathComponent("WorkspaceSession", isDirectory: true),
        defaults: sessionDefaults,
        key: sessionKey
    )

    private struct FileSignature: Equatable {
        let modified: Date?
        let size: Int64?
        let resourceIdentifier: String?
    }

    private static var recoveryDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("NotepadPlus", isDirectory: true)
            .appendingPathComponent("TemporaryDocumentRecovery", isDirectory: true)
    }

    init(preferences: EditorPreferences, defaults: UserDefaults = .standard, recoveryDirectory: URL? = nil) {
        self.preferences = preferences
        self.sessionDefaults = defaults
        self.recoveryRootURL = recoveryDirectory ?? Self.recoveryDirectoryURL
        // Must run before restoreSession: sandbox→unsandboxed upgrades moved
        // Application Support / Preferences out of the Container. Without this
        // merge, nested groups (e.g. 雅江项目 › 人才引进) silently disappear.
        if recoveryDirectory == nil {
            WorkspaceDataMigration.migrateIfNeeded(defaults: defaults)
        }
        restoreAuthorizedFolders()
        restoreWorkspace()
        restoreSession()
        restoreRecentFiles()
        if documents.isEmpty {
            newDocument()
        }
        startFileMonitoring()
    }

    deinit {
        fileMonitorTimer?.invalidate()
        for url in documentSecurityScopedURLs.values { url.stopAccessingSecurityScopedResource() }
        for url in authorizedFolderURLs { url.stopAccessingSecurityScopedResource() }
        workspaceSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    var activeDocument: EditorDocument? {
        guard let activeDocumentID else { return nil }
        return documents.first(where: { $0.id == activeDocumentID })
    }

    var secondaryDocument: EditorDocument? {
        guard let secondaryDocumentID else { return nil }
        return documents.first(where: { $0.id == secondaryDocumentID })
    }

    func scrollOffset(for document: EditorDocument) -> CGPoint {
        document.scrollOffset == .zero
            ? (documentScrollOffsets[document.id] ?? .zero)
            : document.scrollOffset
    }

    func updateScrollOffset(_ offset: CGPoint, for document: EditorDocument) {
        // A representable can be dismantled one run-loop turn after a tab is
        // closed. Ignore that final callback so a closed document cannot
        // repopulate the in-memory viewport cache.
        guard documents.contains(where: { $0.id == document.id }) else { return }
        document.scrollOffset = offset
        documentScrollOffsets[document.id] = offset
    }

    @discardableResult
    func newDocument() -> EditorDocument {
        let title = preferences.tr("新建 \(nextUntitledNumber)", "new \(nextUntitledNumber)")
        nextUntitledNumber += 1
        let targetGroupID = documentGroups.contains(where: { $0.id == selectedGroupID })
            ? selectedGroupID
            : nil
        let document = EditorDocument(title: title, groupID: targetGroupID)
        documents.append(document)
        activeDocumentID = document.id
        persistSession()
        return document
    }

    func activate(_ document: EditorDocument) {
        if let activeDocumentID, activeDocumentID != document.id {
            NotificationCenter.default.post(
                name: .workspaceWillActivateDocument,
                object: activeDocumentID
            )
        }
        activeDocumentID = document.id
        selectedGroupID = document.groupID
        isMarkdownPreviewPresented = false
        persistSession()
    }

    func activateNextDocument(forward: Bool) {
        guard
            documents.count > 1,
            let activeDocumentID,
            let index = documents.firstIndex(where: { $0.id == activeDocumentID })
        else { return }
        let nextIndex = forward
            ? (index + 1) % documents.count
            : (index - 1 + documents.count) % documents.count
        activate(documents[nextIndex])
    }

    func togglePin(_ document: EditorDocument) {
        document.isPinned.toggle()
        documents.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return false
        }
        persistSession()
    }

    func closeUnchangedDocuments(except keptDocument: EditorDocument? = nil) {
        let candidates = documents.filter { !$0.isDirty && $0.id != keptDocument?.id && !$0.isPinned }
        for document in candidates { close(document) }
    }

    func sortDocumentsByName() {
        documents.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        persistSession()
    }

    /// Moves a tab before another tab and persists the user's tab order.
    func moveDocument(_ documentID: UUID, before targetID: UUID) {
        guard documentID != targetID,
              let sourceIndex = documents.firstIndex(where: { $0.id == documentID }),
              let targetIndex = documents.firstIndex(where: { $0.id == targetID })
        else { return }

        let moving = documents.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        documents.insert(moving, at: adjustedTargetIndex)
        persistSession()
    }

    func reload(_ document: EditorDocument, discardingUnsavedChanges: Bool = false) {
        guard discardingUnsavedChanges || !document.isDirty || document.fileAccessError != nil else {
            errorMessage = preferences.tr("文档有未保存更改，保存或放弃更改后才能重新载入。", "Save or discard changes before reloading.")
            return
        }
        guard let url = document.fileURL else { return }
        // Never let a pending autosave rewrite the file we are about to read,
        // or race the UIKit bridge with a stale buffer after the reload.
        autosaveTasks[document.id]?.cancel()
        autosaveTasks[document.id] = nil
        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }
        do {
            // Bypass Foundation's URLCache so we always see the bytes another
            // editor just wrote (atomic replace still updates the path).
            let data = try Data(contentsOf: url, options: [.uncached])
            let decoded = try EditorDocument.decode(data)
            document.applyDiskMetadata(encoding: decoded.encoding, lineEnding: decoded.lineEnding)
            document.updateFromDisk(decoded.text)
            document.fileAccessError = nil
            retainDocumentAccess(to: url, for: document)
            if fileAccessRecoveryURL?.standardizedFileURL == url.standardizedFileURL {
                fileAccessRecoveryURL = nil
            }
            updateFileSignature(for: document)
            suppressExternalChangeUntil[document.id] = Date().addingTimeInterval(1.5)
            NotificationCenter.default.post(
                name: .editorExternalContentReloaded,
                object: document.id
            )
            persistSession()
        } catch {
            document.fileAccessError = error.localizedDescription
            fileAccessRecoveryURL = url
            errorMessage = preferences.tr("重新载入失败：\(error.localizedDescription)", "Reload failed: \(error.localizedDescription)")
        }
    }

    func handleExternalFileChange(reload: Bool) {
        // Prefer the captured change from the alert button. SwiftUI may clear
        // `externalFileChange` before the button action runs (alert(item:) dismiss).
        handleExternalFileChange(externalFileChange, reload: reload)
    }

    func handleExternalFileChange(_ change: ExternalFileChange?, reload: Bool) {
        let resolved = change ?? externalFileChange
        defer { dismissExternalFileChange(resolved) }
        guard let resolved,
              let document = documents.first(where: { $0.id == resolved.documentID })
        else { return }
        if reload {
            // Same path as the tab context-menu “从磁盘重新载入”.
            self.reload(document, discardingUnsavedChanges: true)
        } else {
            // Treat the current on-disk version as acknowledged so the same
            // write does not repeatedly interrupt the user.
            updateFileSignature(for: document)
        }
    }

    private func dismissExternalFileChange(_ change: ExternalFileChange?) {
        if let change {
            pendingExternalFileChanges.removeAll { $0.documentID == change.documentID }
        }
        // SwiftUI may already have nilled the binding before the button ran.
        // Always advance so queued prompts are not stranded.
        if externalFileChange == nil
            || change == nil
            || externalFileChange?.documentID == change?.documentID
            || externalFileChange?.id == change?.id {
            presentNextExternalFileChange()
        }
    }

    /// Live dirty state for the alert — the snapshot can go stale if the user
    /// keeps typing while the dialog is open.
    func isDocumentDirtyForExternalChange(_ change: ExternalFileChange) -> Bool {
        documents.first(where: { $0.id == change.documentID })?.isDirty ?? change.isDirty
    }

    func toggleSplitEditor() {
        if isSplitEditorPresented {
            isSplitEditorPresented = false
            return
        }
        guard documents.count > 1 else {
            errorMessage = preferences.tr("至少打开两个文档后才能使用分栏编辑。", "Open at least two documents to use split editing.")
            return
        }
        if secondaryDocumentID == nil || secondaryDocumentID == activeDocumentID {
            secondaryDocumentID = documents.first(where: { $0.id != activeDocumentID })?.id
        }
        isSplitEditorPresented = secondaryDocument != nil
    }

    func open(urls: [URL]) {
        for url in urls {
            open(url: url)
        }
    }

    func open(url: URL, onOpen: ((EditorDocument) -> Void)? = nil) {
        if let existing = documents.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            existing.fileURL = url
            retainDocumentAccess(to: url, for: existing)
            if existing.fileAccessError != nil { reload(existing) }
            activate(existing)
            addRecentFile(url)
            onOpen?(existing)
            return
        }

        let normalizedURL = url.standardizedFileURL
        guard !loadingFileURLs.contains(normalizedURL) else { return }

        let granted = url.startAccessingSecurityScopedResource()
        loadingFileURLs.insert(normalizedURL)

        Task { [weak self] in
            do {
                let decoded = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                    return try EditorDocument.decode(data)
                }.value

                guard let self else {
                    if granted { url.stopAccessingSecurityScopedResource() }
                    return
                }
                self.loadingFileURLs.remove(normalizedURL)
                defer { if granted { url.stopAccessingSecurityScopedResource() } }

                // The file may have been opened through a second request while
                // the first read was in progress. Reuse the existing tab.
                if let existing = self.documents.first(where: {
                    $0.fileURL?.standardizedFileURL == normalizedURL
                }) {
                    self.activate(existing)
                    self.addRecentFile(url)
                    return
                }

                let document = EditorDocument(
                    title: url.lastPathComponent,
                    content: decoded.text,
                    fileURL: url,
                    language: SyntaxLanguage.detect(filename: url.lastPathComponent),
                    encoding: decoded.encoding,
                    lineEnding: decoded.lineEnding
                )
                self.documents.append(document)
                self.retainDocumentAccess(to: url, for: document)
                if self.fileAccessRecoveryURL?.standardizedFileURL == url.standardizedFileURL {
                    self.fileAccessRecoveryURL = nil
                }
                self.activeDocumentID = document.id
                self.updateFileSignature(for: document)
                self.selectedGroupID = nil
                self.addRecentFile(url)
                self.persistSession()
                onOpen?(document)
            } catch {
                self?.loadingFileURLs.remove(normalizedURL)
                if granted { url.stopAccessingSecurityScopedResource() }
                self?.fileAccessRecoveryURL = url
                self?.errorMessage = self?.preferences.tr(
                    "无法打开 \(url.lastPathComponent)：\(error.localizedDescription)",
                    "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }
    }

    func openWorkspace(url: URL) {
        if let workspaceSecurityScopedURL {
            workspaceSecurityScopedURL.stopAccessingSecurityScopedResource()
            self.workspaceSecurityScopedURL = nil
        }
        let granted = url.startAccessingSecurityScopedResource()
        guard granted || url.isFileURL else {
            errorMessage = preferences.tr("无法访问所选文件夹。", "The selected folder could not be accessed.")
            return
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            if granted { url.stopAccessingSecurityScopedResource() }
            errorMessage = preferences.tr("无法读取所选文件夹。", "The selected folder could not be read.")
            return
        }

        workspaceFolder = url
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            guard files.count < 500 else { break }
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true, values?.isHidden != true {
                files.append(fileURL)
            }
        }
        workspaceFiles = files.sorted {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        if granted {
            workspaceSecurityScopedURL = url
        }
        persistWorkspaceBookmark(for: url)
    }

    func save(_ document: EditorDocument, to destination: URL? = nil) throws {
        guard document.fileAccessError == nil else {
            fileAccessRecoveryURL = document.fileURL
            throw CocoaError(.fileReadNoPermission, userInfo: [
                NSLocalizedDescriptionKey: preferences.tr("请先重新授权并载入文件，再保存。", "Reauthorize and load this file before saving.")
            ])
        }
        guard let url = destination ?? document.fileURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "保存此文档前请选择保存位置。"
            ])
        }

        let granted = url.startAccessingSecurityScopedResource()
        defer {
            if granted { url.stopAccessingSecurityScopedResource() }
        }

        guard let data = document.textForSaving.data(using: document.encoding.stringEncoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            fileAccessRecoveryURL = url
            throw error
        }
        if document.fileURL?.standardizedFileURL != url.standardizedFileURL {
            document.securityScopedBookmark = nil
        }
        document.markSaved(at: url)
        retainDocumentAccess(to: url, for: document)
        updateFileSignature(for: document)
        // Atomic replace usually bumps mtime; suppress the next poll cycles
        // so we do not prompt the user about their own save.
        suppressExternalChangeUntil[document.id] = Date().addingTimeInterval(2.5)
        scratchRecoveryStore.remove(id: document.id)
        addRecentFile(url)
        persistSession()
    }

    func close(_ document: EditorDocument) {
        autosaveTasks[document.id]?.cancel()
        recoveryPersistenceTasks[document.id]?.cancel()
        recoveryPersistenceTasks[document.id] = nil
        fileSignatures.removeValue(forKey: document.id)
        suppressExternalChangeUntil.removeValue(forKey: document.id)
        pendingExternalFileChanges.removeAll { $0.documentID == document.id }
        if externalFileChange?.documentID == document.id {
            presentNextExternalFileChange()
        }
        scratchRecoveryStore.remove(id: document.id)
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents.remove(at: index)
        documentSecurityScopedURLs.removeValue(forKey: document.id)?.stopAccessingSecurityScopedResource()
        documentScrollOffsets[document.id] = nil
        ScrollPositionStore.shared.remove(for: document.id)
        if secondaryDocumentID == document.id {
            secondaryDocumentID = documents.first(where: { $0.id != activeDocumentID })?.id
            if secondaryDocumentID == nil { isSplitEditorPresented = false }
        }

        if activeDocumentID == document.id {
            if documents.indices.contains(index) {
                activeDocumentID = documents[index].id
            } else {
                activeDocumentID = documents.last?.id
            }
        }

        if documents.isEmpty {
            newDocument()
        } else {
            persistSession()
        }
    }

    private func startFileMonitoring() {
        fileMonitorTimer?.invalidate()
        fileMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pollFileChanges() }
        }
        documents.forEach { updateFileSignature(for: $0) }
    }

    private func pollFileChanges() {
        for document in documents {
            guard document.fileURL != nil, document.fileAccessError == nil else { continue }
            let current = fileSignature(for: document.fileURL, documentID: document.id)
            guard let previous = fileSignatures[document.id] else {
                fileSignatures[document.id] = current
                continue
            }
            guard current != previous else { continue }

            if let until = suppressExternalChangeUntil[document.id], until > Date() {
                // Absorb our own write's mtime update without prompting.
                fileSignatures[document.id] = current
                continue
            }

            // Keep the previous signature until the user answers so a missed
            // or dismissed alert can still be re-detected on the next poll.
            enqueueExternalFileChange(
                ExternalFileChange(
                    id: UUID(),
                    documentID: document.id,
                    fileName: document.fileURL?.lastPathComponent ?? document.title,
                    isDirty: document.isDirty
                )
            )
            // Advance the baseline only after we have queued a prompt, so
            // repeated polls of the same on-disk revision do not spam.
            fileSignatures[document.id] = current
            // Stop autosave from overwriting the external revision while the
            // user is still deciding whether to reload.
            autosaveTasks[document.id]?.cancel()
            autosaveTasks[document.id] = nil
        }
    }

    private func enqueueExternalFileChange(_ change: ExternalFileChange) {
        if externalFileChange?.documentID == change.documentID { return }
        if pendingExternalFileChanges.contains(where: { $0.documentID == change.documentID }) { return }
        if externalFileChange == nil {
            externalFileChange = change
        } else {
            pendingExternalFileChanges.append(change)
        }
    }

    private func presentNextExternalFileChange() {
        if pendingExternalFileChanges.isEmpty {
            externalFileChange = nil
            return
        }
        // Drop entries for documents that were closed while waiting.
        while let next = pendingExternalFileChanges.first {
            pendingExternalFileChanges.removeFirst()
            if documents.contains(where: { $0.id == next.documentID }) {
                externalFileChange = ExternalFileChange(
                    id: next.id,
                    documentID: next.documentID,
                    fileName: next.fileName,
                    isDirty: documents.first(where: { $0.id == next.documentID })?.isDirty ?? next.isDirty
                )
                return
            }
        }
        externalFileChange = nil
    }

    private func updateFileSignature(for document: EditorDocument) {
        fileSignatures[document.id] = fileSignature(for: document.fileURL, documentID: document.id)
    }

    private func fileSignature(for url: URL?, documentID: UUID? = nil) -> FileSignature? {
        guard let url else { return nil }
        // Prefer the long-lived security-scoped URL retained for this document;
        // a bare bookmark URL often fails resourceValues under sandbox without
        // an active access grant, which silently disabled change detection.
        let scoped = documentID.flatMap { documentSecurityScopedURLs[$0] }
        let probe = scoped ?? url
        let granted = probe.startAccessingSecurityScopedResource()
        defer { if granted { probe.stopAccessingSecurityScopedResource() } }
        let values = try? probe.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey,
            .fileResourceIdentifierKey
        ])
        guard values?.contentModificationDate != nil || values?.fileSize != nil || values?.fileResourceIdentifier != nil else {
            return nil
        }
        return FileSignature(
            modified: values?.contentModificationDate,
            size: values?.fileSize.map(Int64.init),
            resourceIdentifier: values?.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    func documentDidChange(_ document: EditorDocument) {
        guard document.fileAccessError == nil else { return }
        // Do not autosave over a file the user has been warned is externally
        // changed — that race was discarding the other app's edits.
        if externalFileChange?.documentID == document.id
            || pendingExternalFileChanges.contains(where: { $0.documentID == document.id }) {
            schedulePersistence(for: document)
            return
        }
        schedulePersistence(for: document)
        guard preferences.autoSave, document.fileURL != nil, document.isDirty else { return }
        autosaveTasks[document.id]?.cancel()
        autosaveTasks[document.id] = Task { [weak self, weak document] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self, let document, document.isDirty else { return }
            if self.externalFileChange?.documentID == document.id { return }
            do {
                try self.save(document)
            } catch {
                self.errorMessage = self.preferences.tr(
                    "自动保存失败：\(error.localizedDescription)",
                    "Autosave failed: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Flushes debounced editor changes before the app is backgrounded or terminated.
    /// This keeps typing responsive without weakening temporary-document recovery.
    func flushPendingChanges() {
        sessionPersistenceTask?.cancel()
        sessionPersistenceTask = nil
        for task in recoveryPersistenceTasks.values { task.cancel() }
        recoveryPersistenceTasks.removeAll()
        persistSession()
    }

    func apply(_ transformation: TextTransformation, to document: EditorDocument) {
        guard document.fileAccessError == nil else { return }
        let nsText = document.content as NSString
        let range = document.selection
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: nsText.length))

        if safeRange.length > 0 {
            let selected = nsText.substring(with: safeRange)
            let replacement = transformation.apply(to: selected)
            document.content = nsText.replacingCharacters(in: safeRange, with: replacement)
            document.selection = NSRange(location: safeRange.location, length: (replacement as NSString).length)
        } else {
            document.content = transformation.apply(to: document.content)
        }
        documentDidChange(document)
    }

    func apply(_ action: LineEditingAction, to document: EditorDocument) {
        guard document.fileAccessError == nil else { return }
        let result = LineEditingEngine.apply(
            action,
            to: document.content,
            selection: document.selection,
            language: document.language
        )
        guard result.text != document.content else { return }
        document.content = result.text
        document.selection = result.selection
        documentDidChange(document)
    }

    func applyColumnEdit(
        to document: EditorDocument,
        startLine: Int,
        endLine: Int,
        column: Int,
        value: String,
        overwrite: Bool
    ) {
        guard document.fileAccessError == nil else { return }
        let result = ColumnEditingEngine.apply(
            to: document.content,
            startLine: startLine,
            endLine: endLine,
            column: column,
            value: value,
            overwrite: overwrite
        )
        guard result.text != document.content else { return }
        document.content = result.text
        document.selection = result.selection
        documentDidChange(document)
    }

    @discardableResult
    func addDocumentGroup(named name: String, parentID: UUID? = nil) -> DocumentGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard parentID == nil || documentGroups.contains(where: { $0.id == parentID }) else { return nil }
        let group = DocumentGroup(name: trimmed, parentID: parentID)
        documentGroups.append(group)
        selectedGroupID = group.id
        persistSession()
        return group
    }

    var groupHierarchy: GroupHierarchy {
        GroupHierarchy(documentGroups.map { WorkspaceSessionGroup(id: $0.id, name: $0.name, color: $0.color.rawValue, parentID: $0.parentID) })
    }

    func moveDocumentGroup(_ group: DocumentGroup, to parentID: UUID?) {
        guard groupHierarchy.canMove(group.id, to: parentID),
              let index = documentGroups.firstIndex(where: { $0.id == group.id }) else { return }
        documentGroups[index].parentID = parentID
        persistSession()
    }

    func renameDocumentGroup(_ group: DocumentGroup, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = documentGroups.firstIndex(where: { $0.id == group.id }) else { return }
        documentGroups[index].name = trimmed
        persistSession()
    }

    func setColor(_ color: DocumentGroupColor, for group: DocumentGroup) {
        guard let index = documentGroups.firstIndex(where: { $0.id == group.id }) else { return }
        documentGroups[index].color = color
        persistSession()
    }

    func selectGroup(_ group: DocumentGroup?) {
        selectedGroupID = group?.id
        persistSession()
    }

    func removeDocumentGroup(_ group: DocumentGroup) {
        guard let current = documentGroups.first(where: { $0.id == group.id }) else { return }
        documentGroups.removeAll(where: { $0.id == group.id })
        for index in documentGroups.indices where documentGroups[index].parentID == group.id {
            documentGroups[index].parentID = current.parentID
        }
        if selectedGroupID == group.id { selectedGroupID = current.parentID }
        for document in documents where document.groupID == group.id {
            document.groupID = current.parentID
        }
        persistSession()
    }

    func assign(_ document: EditorDocument, to group: DocumentGroup?) {
        guard document.groupID != group?.id else { return }
        objectWillChange.send()
        document.groupID = group?.id
        selectedGroupID = group?.id
        persistSession()
    }

    func moveDocumentGroup(_ group: DocumentGroup, before target: DocumentGroup) {
        guard group.id != target.id,
              let sourceIndex = documentGroups.firstIndex(where: { $0.id == group.id }),
              let targetIndex = documentGroups.firstIndex(where: { $0.id == target.id })
        else { return }
        guard groupHierarchy.canMove(group.id, to: target.parentID) else { return }
        var moving = documentGroups.remove(at: sourceIndex)
        moving.parentID = target.parentID
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        documentGroups.insert(moving, at: insertionIndex)
        persistSession()
    }

    func rename(_ document: EditorDocument, to proposedName: String) {
        guard document.fileAccessError == nil else {
            requestFileAccess(for: document)
            return
        }
        let newName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else { return }
        guard let oldURL = document.fileURL else {
            document.title = newName
            document.language = SyntaxLanguage.detect(filename: newName)
            persistSession()
            return
        }
        let destination = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        guard destination != oldURL else { return }
        let granted = oldURL.startAccessingSecurityScopedResource()
        defer {
            if granted { oldURL.stopAccessingSecurityScopedResource() }
        }
        do {
            try FileManager.default.moveItem(at: oldURL, to: destination)
            document.fileURL = destination
            document.securityScopedBookmark = nil
            retainDocumentAccess(to: destination, for: document)
            document.title = newName
            document.language = SyntaxLanguage.detect(filename: newName)
            updateFileSignature(for: document)
            recentFiles.removeAll(where: { $0.standardizedFileURL == oldURL.standardizedFileURL })
            addRecentFile(destination)
            persistSession()
        } catch {
            errorMessage = preferences.tr("重命名失败：\(error.localizedDescription)", "Rename failed: \(error.localizedDescription)")
        }
    }

    func toggleBookmark(in document: EditorDocument) {
        document.toggleBookmark()
        bottomPanelMode = .bookmarks
        isBottomPanelPresented = true
        persistSession()
    }

    func showBottomPanel(_ mode: BottomPanelMode) {
        bottomPanelMode = mode
        isBottomPanelPresented = true
    }

    func saveAllExistingDocuments() {
        var failures: [String] = []
        for document in documents where document.isDirty && document.fileURL != nil {
            do {
                try save(document)
            } catch {
                failures.append(preferences.tr(
                    "保存 \(document.title) 失败：\(error.localizedDescription)",
                    "Could not save \(document.title): \(error.localizedDescription)"
                ))
            }
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    func searchWorkspace(in range: NSRange? = nil) {
        switch workspaceSearchScope {
        case .currentDocument:
            searchCurrentDocument(in: range)
        case .allOpenDocuments:
            searchOpenDocuments()
        case .workspaceFolder:
            searchFolderWorkspace()
        }
    }

    private func searchCurrentDocument(in range: NSRange? = nil) {
        guard let document = activeDocument else { workspaceSearchResults = []; return }
        do {
            let matches = try SearchEngine.matches(in: document.content, query: workspaceSearchQuery, options: workspaceSearchOptions, in: range)
            publishSearchHighlights(for: document, ranges: matches)
            let nsText = document.content as NSString
            let displayURL = document.fileURL ?? URL(fileURLWithPath: document.title)
            workspaceSearchResults = matches.prefix(1_000).map { match in
                let position = TextStatistics.lineAndColumn(in: document.content, utf16Location: match.location)
                let snippet = nsText.substring(with: nsText.lineRange(for: match)).trimmingCharacters(in: .whitespacesAndNewlines)
                let snippetMatches = (try? SearchEngine.matches(in: snippet, query: workspaceSearchQuery, options: workspaceSearchOptions)) ?? []
                return WorkspaceSearchResult(fileURL: displayURL, documentID: document.id, line: position.line, column: position.column, snippet: snippet, selection: match, snippetMatches: snippetMatches)
            }
            showBottomPanel(.search)
        } catch {
            workspaceSearchResults = []
            errorMessage = preferences.tr("搜索失败：\(error.localizedDescription)", "Search failed: \(error.localizedDescription)")
        }
    }

    private func searchOpenDocuments() {
        guard !workspaceSearchQuery.isEmpty else {
            workspaceSearchResults = []
            if let activeDocument { publishSearchHighlights(for: activeDocument, ranges: []) }
            return
        }
        do {
            var results: [WorkspaceSearchResult] = []
            for document in documents {
                guard results.count < 1_000 else { break }
                let matches = try SearchEngine.matches(in: document.content, query: workspaceSearchQuery, options: workspaceSearchOptions)
                let nsText = document.content as NSString
                let displayURL = document.fileURL ?? URL(fileURLWithPath: document.title)
                for match in matches {
                    guard results.count < 1_000 else { break }
                    let position = TextStatistics.lineAndColumn(in: document.content, utf16Location: match.location)
                    let snippet = nsText.substring(with: nsText.lineRange(for: match)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let snippetMatches = (try? SearchEngine.matches(in: snippet, query: workspaceSearchQuery, options: workspaceSearchOptions)) ?? []
                    results.append(WorkspaceSearchResult(fileURL: displayURL, documentID: document.id, line: position.line, column: position.column, snippet: snippet, selection: match, snippetMatches: snippetMatches))
                }
            }
            workspaceSearchResults = results
            if let activeDocument {
                let activeMatches = try SearchEngine.matches(in: activeDocument.content, query: workspaceSearchQuery, options: workspaceSearchOptions)
                publishSearchHighlights(for: activeDocument, ranges: activeMatches)
            }
            showBottomPanel(.search)
        } catch {
            workspaceSearchResults = []
            errorMessage = preferences.tr("搜索失败：\(error.localizedDescription)", "Search failed: \(error.localizedDescription)")
        }
    }

    private func searchFolderWorkspace() {
        guard !workspaceSearchQuery.isEmpty else {
            workspaceSearchResults = []
            if let activeDocument { publishSearchHighlights(for: activeDocument, ranges: []) }
            return
        }
        guard workspaceFolder != nil else {
            workspaceSearchResults = []
            errorMessage = preferences.tr("使用“在文件中查找”前，请先打开文件夹工作区。", "Open a folder workspace before using Find in Files.")
            return
        }

        var results: [WorkspaceSearchResult] = []
        do {
            for url in workspaceFiles {
                guard results.count < 1_000 else { break }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                guard (values?.fileSize ?? 0) <= 4_000_000 else { continue }
                let data = try Data(contentsOf: url)
                guard let decoded = try? EditorDocument.decode(data) else { continue }
                let text = decoded.text
                let matches = try SearchEngine.matches(
                    in: text,
                    query: workspaceSearchQuery,
                    options: workspaceSearchOptions
                )
                let nsText = text as NSString
                for match in matches {
                    guard results.count < 1_000 else { break }
                    let position = TextStatistics.lineAndColumn(in: text, utf16Location: match.location)
                    let lineRange = nsText.lineRange(for: match)
                    let snippet = nsText.substring(with: lineRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let snippetMatches = (try? SearchEngine.matches(in: snippet, query: workspaceSearchQuery, options: workspaceSearchOptions)) ?? []
                    results.append(WorkspaceSearchResult(
                        fileURL: url,
                        documentID: documents.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL })?.id,
                        line: position.line,
                        column: position.column,
                        snippet: snippet,
                        selection: match,
                        snippetMatches: snippetMatches
                    ))
                }
            }
            workspaceSearchResults = results
            if let activeDocument {
                let activeMatches = try SearchEngine.matches(in: activeDocument.content, query: workspaceSearchQuery, options: workspaceSearchOptions)
                publishSearchHighlights(for: activeDocument, ranges: activeMatches)
            }
            showBottomPanel(.search)
        } catch {
            workspaceSearchResults = []
            errorMessage = preferences.tr("搜索失败：\(error.localizedDescription)", "Search failed: \(error.localizedDescription)")
        }
    }

    private func publishSearchHighlights(for document: EditorDocument, ranges: [NSRange]) {
        NotificationCenter.default.post(
            name: .editorSearchHighlightsChanged,
            object: SearchHighlightRequest(documentID: document.id, ranges: ranges)
        )
    }

    func replaceAllInWorkspace() {
        guard !workspaceSearchQuery.isEmpty, workspaceFolder != nil else { return }
        var replacementCount = 0
        var changedFiles = 0
        do {
            for url in workspaceFiles {
                if let openDocument = documents.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
                    guard openDocument.fileAccessError == nil else { continue }
                    let result = try SearchEngine.replaceAll(
                        in: openDocument.content,
                        query: workspaceSearchQuery,
                        replacement: workspaceSearchReplacement,
                        options: workspaceSearchOptions
                    )
                    if result.count > 0 {
                        openDocument.content = result.text
                        documentDidChange(openDocument)
                        replacementCount += result.count
                        changedFiles += 1
                    }
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                guard (values?.fileSize ?? 0) <= 4_000_000 else { continue }
                let data = try Data(contentsOf: url)
                guard let decoded = try? EditorDocument.decode(data) else { continue }
                let result = try SearchEngine.replaceAll(
                    in: decoded.text,
                    query: workspaceSearchQuery,
                    replacement: workspaceSearchReplacement,
                    options: workspaceSearchOptions
                )
                guard result.count > 0 else { continue }
                let output = decoded.lineEnding == .lf
                    ? result.text
                    : result.text.replacingOccurrences(of: "\n", with: decoded.lineEnding.sequence)
                guard let outputData = output.data(using: decoded.encoding.stringEncoding) else { continue }
                try outputData.write(to: url, options: .atomic)
                replacementCount += result.count
                changedFiles += 1
            }
            searchWorkspace()
            errorMessage = preferences.tr(
                "已在 \(changedFiles) 个文件中完成 \(replacementCount) 处替换。",
                "Replaced \(replacementCount) matches in \(changedFiles) files."
            )
        } catch {
            errorMessage = preferences.tr("替换失败：\(error.localizedDescription)", "Replace failed: \(error.localizedDescription)")
        }
    }

    /// Replace all matches using the same scope selected in the Find in Files
    /// panel. This mirrors Notepad++'s Current document / All opened
    /// documents / Current folder choices and keeps the destructive action in
    /// one place for both the panel and the find bar.
    func replaceAllInSearchScope() {
        switch workspaceSearchScope {
        case .workspaceFolder:
            replaceAllInWorkspace()
        case .currentDocument:
            guard let document = activeDocument, !workspaceSearchQuery.isEmpty else { return }
            replaceAll(in: [document], writeClosedFiles: false)
        case .allOpenDocuments:
            guard !workspaceSearchQuery.isEmpty else { return }
            replaceAll(in: documents, writeClosedFiles: false)
        }
    }

    private func replaceAll(in documentsToUpdate: [EditorDocument], writeClosedFiles: Bool) {
        var replacementCount = 0
        var changedDocuments = 0
        do {
            for document in documentsToUpdate {
                guard document.fileAccessError == nil else { continue }
                let result = try SearchEngine.replaceAll(
                    in: document.content,
                    query: workspaceSearchQuery,
                    replacement: workspaceSearchReplacement,
                    options: workspaceSearchOptions
                )
                guard result.count > 0 else { continue }
                document.content = result.text
                documentDidChange(document)
                replacementCount += result.count
                changedDocuments += 1
            }
            searchWorkspace()
            errorMessage = preferences.tr(
                "已在 \(changedDocuments) 个打开文档中完成 \(replacementCount) 处替换。",
                "Replaced \(replacementCount) matches in \(changedDocuments) open documents."
            )
        } catch {
            errorMessage = preferences.tr("替换失败：\(error.localizedDescription)", "Replace failed: \(error.localizedDescription)")
        }
    }

    func open(searchResult: WorkspaceSearchResult) {
        let resultKey = "\(searchResult.fileURL.standardizedFileURL.path)#\(searchResult.selection.location):\(searchResult.selection.length)"
        let now = Date()
        if lastSearchRevealKey == resultKey,
           let lastSearchRevealDate,
           now.timeIntervalSince(lastSearchRevealDate) < 0.35 {
            return
        }
        lastSearchRevealKey = resultKey
        lastSearchRevealDate = now
        if let documentID = searchResult.documentID,
           let document = documents.first(where: { $0.id == documentID }) {
            activate(document)
            document.selection = searchResult.selection
            SearchRevealStore.shared.set(searchResult.selection, for: document.id)
            NotificationCenter.default.post(
                name: .editorSearchRevealSelection,
                object: SearchSelectionRequest(documentID: document.id, selection: searchResult.selection)
            )
            return
        }
        open(url: searchResult.fileURL) { [weak self] document in
            guard let self else { return }
            self.activate(document)
            document.selection = searchResult.selection
            SearchRevealStore.shared.set(searchResult.selection, for: document.id)
            NotificationCenter.default.post(
                name: .editorSearchRevealSelection,
                object: SearchSelectionRequest(documentID: document.id, selection: searchResult.selection)
            )
        }
    }

    func markAllSearchMatches(in document: EditorDocument, clearExisting: Bool = false, range: NSRange? = nil) {
        guard !workspaceSearchQuery.isEmpty else { return }
        do {
            let matches = try SearchEngine.matches(in: document.content, query: workspaceSearchQuery, options: workspaceSearchOptions, in: range)
            if clearExisting { document.bookmarks.removeAll() }
            for match in matches {
                document.bookmarks.insert(TextStatistics.lineAndColumn(in: document.content, utf16Location: match.location).line)
            }
            persistSession()
            bottomPanelMode = .bookmarks
            isBottomPanelPresented = true
        } catch {
            errorMessage = preferences.tr("标记失败：\(error.localizedDescription)", "Mark all failed: \(error.localizedDescription)")
        }
    }

    func clearSearchMarks(in document: EditorDocument? = nil) {
        if let document {
            document.bookmarks.removeAll()
        } else {
            documents.forEach { $0.bookmarks.removeAll() }
        }
        persistSession()
    }

    func duplicateActiveDocument() {
        guard let source = activeDocument else { return }
        let copy = EditorDocument(
            title: "\(source.title) copy",
            content: source.content,
            isDirty: true,
            language: source.language,
            encoding: source.encoding,
            lineEnding: source.lineEnding
        )
        documents.append(copy)
        activeDocumentID = copy.id
        persistSession()
    }

    private func addRecentFile(_ url: URL) {
        recentFiles.removeAll(where: { $0.standardizedFileURL == url.standardizedFileURL })
        recentFiles.insert(url, at: 0)
        recentFiles = Array(recentFiles.prefix(10))
        persistRecentFiles()
    }

    func removeRecentFile(_ url: URL) {
        recentFiles.removeAll(where: { $0.standardizedFileURL == url.standardizedFileURL })
        persistRecentFiles()
    }

    func clearRecentFiles() {
        recentFiles.removeAll()
        persistRecentFiles()
    }

    private struct RecentBookmark: Codable {
        let path: String
        let bookmark: Data?
    }

    private func persistRecentFiles() {
        sessionDefaults.set(recentFiles.map(\.path), forKey: recentKey)
        let saved = recentFiles.map { url in
            let bookmark = securityScopedBookmark(for: url) ?? recentFileBookmarks[url.path]
            recentFileBookmarks[url.path] = bookmark
            return RecentBookmark(path: url.path, bookmark: bookmark)
        }
        recentFileBookmarks = recentFileBookmarks.filter { path, _ in recentFiles.contains { $0.path == path } }
        if let data = try? JSONEncoder().encode(saved) {
            sessionDefaults.set(data, forKey: recentBookmarksKey)
        }
    }

    private func restoreRecentFiles() {
        if
            let data = sessionDefaults.data(forKey: recentBookmarksKey),
            let saved = try? JSONDecoder().decode([RecentBookmark].self, from: data)
        {
            recentFiles = saved.map { record in
                let url = record.bookmark.flatMap(resolveSecurityScopedBookmark) ?? URL(fileURLWithPath: record.path)
                if let bookmark = record.bookmark { recentFileBookmarks[url.path] = bookmark }
                return url
            }
            return
        }
        let paths = sessionDefaults.stringArray(forKey: recentKey) ?? []
        recentFiles = paths.map { URL(fileURLWithPath: $0) }
    }

    private func schedulePersistence(for document: EditorDocument) {
        recoveryPersistenceTasks[document.id]?.cancel()
        recoveryPersistenceTasks[document.id] = Task { [weak self, weak document] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self, let document,
                  self.documents.contains(where: { $0.id == document.id })
            else { return }
            if document.fileURL == nil {
                self.persistRecoverySnapshot(for: document)
            }
            self.recoveryPersistenceTasks[document.id] = nil
        }

        sessionPersistenceTask?.cancel()
        sessionPersistenceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self else { return }
            self.persistSession(writeRecoverySnapshots: false)
            self.sessionPersistenceTask = nil
        }
    }

    private func persistSession(writeRecoverySnapshots: Bool = true) {
        // A failed decode must never overwrite the only surviving session.
        guard !isSessionPersistenceBlocked else { return }
        if writeRecoverySnapshots {
            for document in documents where document.fileURL == nil {
                persistRecoverySnapshot(for: document)
            }
        }
        let persisted = documents.map { document in
            if let url = document.fileURL,
               let bookmark = securityScopedBookmark(for: url) {
                document.securityScopedBookmark = bookmark
            }
            return WorkspaceSessionDocument(
                id: document.id,
                title: document.title,
                scratchContent: document.fileURL == nil ? document.content : nil,
                path: document.fileURL?.path,
                securityScopedBookmark: document.securityScopedBookmark,
                language: document.language.rawValue,
                encoding: document.encoding.rawValue,
                lineEnding: document.lineEnding.rawValue,
                bookmarks: document.bookmarks,
                groupID: document.groupID,
                isPinned: document.isPinned
            )
        }
        let session = WorkspaceSessionSnapshot(
            documents: persisted,
            activeID: activeDocumentID,
            groups: documentGroups.map { WorkspaceSessionGroup(id: $0.id, name: $0.name, color: $0.color.rawValue, parentID: $0.parentID) },
            selectedGroupID: selectedGroupID
        )
        do {
            try sessionArchive.save(session)
        } catch {
            errorMessage = preferences.tr("分组与会话备份保存失败：\(error.localizedDescription)", "Could not save workspace groups and session: \(error.localizedDescription)")
        }
    }

    private func restoreSession() {
        let session: WorkspaceSessionSnapshot?
        do {
            session = try sessionArchive.load()
        } catch {
            session = nil
            isSessionPersistenceBlocked = true
            errorMessage = preferences.tr(
                "原有分组与会话数据暂时无法读取，已停止覆盖原数据。请保留应用数据并联系开发者恢复。\n\(error.localizedDescription)",
                "The saved groups and session could not be read. The original data will not be overwritten. Keep the app data and contact support.\n\(error.localizedDescription)"
            )
        }

        if let session {
            documentGroups = GroupHierarchy(session.groups ?? []).groups.map {
                DocumentGroup(id: $0.id, name: $0.name, color: DocumentGroupColor(rawValue: $0.color ?? "") ?? .green, parentID: $0.parentID)
            }
            documents = session.documents.map { saved in
                if let scratch = saved.scratchContent {
                    return EditorDocument(
                        id: saved.id,
                        title: saved.title,
                        content: scratch,
                        isDirty: !scratch.isEmpty,
                        bookmarks: saved.bookmarks ?? [],
                        groupID: saved.groupID,
                        isPinned: saved.isPinned ?? false,
                        language: SyntaxLanguage(rawValue: saved.language ?? "") ?? .plainText,
                        encoding: DocumentEncoding(rawValue: saved.encoding ?? "") ?? .utf8,
                        lineEnding: LineEnding(rawValue: saved.lineEnding ?? "") ?? .lf
                    )
                }

                // The archive validates that every entry has content or a path.
                let url = saved.securityScopedBookmark.flatMap(resolveSecurityScopedBookmark)
                    ?? URL(fileURLWithPath: saved.path!)
                let document = EditorDocument(
                    id: saved.id,
                    title: saved.title,
                    fileURL: url,
                    bookmarks: saved.bookmarks ?? [],
                    groupID: saved.groupID,
                    isPinned: saved.isPinned ?? false,
                    language: SyntaxLanguage(rawValue: saved.language ?? "") ?? .plainText,
                    encoding: DocumentEncoding(rawValue: saved.encoding ?? "") ?? .utf8,
                    lineEnding: LineEnding(rawValue: saved.lineEnding ?? "") ?? .lf
                )
                document.securityScopedBookmark = saved.securityScopedBookmark
                retainDocumentAccess(to: url, for: document)
                do {
                    let decoded = try EditorDocument.decode(Data(contentsOf: url))
                    document.encoding = decoded.encoding
                    document.lineEnding = decoded.lineEnding
                    document.updateFromDisk(decoded.text)
                } catch {
                    // Permission errors and missing drives are recoverable states,
                    // never a reason to delete the file or its group membership.
                    document.fileAccessError = error.localizedDescription
                }
                return document
            }
            activeDocumentID = documents.contains(where: { $0.id == session.activeID })
                ? session.activeID
                : documents.first?.id
            selectedGroupID = documentGroups.contains(where: { $0.id == session.selectedGroupID })
                ? session.selectedGroupID
                : nil
        }

        restoreRecoveryDocuments()
        if activeDocumentID == nil { activeDocumentID = documents.first?.id }
        nextUntitledNumber = documents.count + 1
    }

    private func persistRecoverySnapshot(for document: EditorDocument) {
        guard document.fileURL == nil else {
            scratchRecoveryStore.remove(id: document.id)
            return
        }
        let group = document.groupID.flatMap { id in
            documentGroups.first(where: { $0.id == id })
        }
        let record = ScratchRecoveryRecord(
            id: document.id,
            title: document.title,
            content: document.content,
            language: document.language.rawValue,
            encoding: document.encoding.rawValue,
            lineEnding: document.lineEnding.rawValue,
            bookmarks: document.bookmarks,
            groupID: group?.id,
            groupName: group?.name,
            groupColor: group?.color.rawValue,
            groupAncestors: group.map { group in
                let ids = groupHierarchy.ancestors(of: group.id).reversed()
                return ids.compactMap { id in groupHierarchy.groups.first(where: { $0.id == id }) }
            },
            isPinned: document.isPinned
        )
        do {
            try scratchRecoveryStore.save(record)
        } catch {
            errorMessage = preferences.tr(
                "临时文档恢复备份写入失败：\(error.localizedDescription)",
                "Could not write the temporary document recovery copy: \(error.localizedDescription)"
            )
        }
    }

    private func restoreRecoveryDocuments() {
        let knownIDs = Set(documents.map(\.id))
        let records = scratchRecoveryStore.loadAll()
        for record in records where !knownIDs.contains(record.id) {
            for ancestor in record.groupAncestors ?? [] where !documentGroups.contains(where: { $0.id == ancestor.id }) {
                documentGroups.append(DocumentGroup(id: ancestor.id, name: ancestor.name,
                    color: DocumentGroupColor(rawValue: ancestor.color ?? "") ?? .green, parentID: ancestor.parentID))
            }
            if let groupID = record.groupID,
               !documentGroups.contains(where: { $0.id == groupID }),
               let groupName = record.groupName {
                documentGroups.append(DocumentGroup(
                    id: groupID,
                    name: groupName,
                    color: DocumentGroupColor(rawValue: record.groupColor ?? "") ?? .green,
                    parentID: record.groupAncestors?.last?.id
                ))
            }
            documents.append(EditorDocument(
                id: record.id,
                title: record.title,
                content: record.content,
                isDirty: !record.content.isEmpty,
                bookmarks: record.bookmarks,
                groupID: documentGroups.contains(where: { $0.id == record.groupID }) ? record.groupID : nil,
                isPinned: record.isPinned,
                language: SyntaxLanguage(rawValue: record.language) ?? .plainText,
                encoding: DocumentEncoding(rawValue: record.encoding) ?? .utf8,
                lineEnding: LineEnding(rawValue: record.lineEnding) ?? .lf
            ))
        }

        let parents = Dictionary(uniqueKeysWithValues: groupHierarchy.groups.map { ($0.id, $0.parentID) })
        for index in documentGroups.indices { documentGroups[index].parentID = parents[documentGroups[index].id] ?? nil }

        // 将旧版 UserDefaults 中的临时文档立即迁移到独立恢复保险库。
        for document in documents where document.fileURL == nil {
            persistRecoverySnapshot(for: document)
        }
    }

    private func securityScopedBookmark(for url: URL) -> Data? {
        #if targetEnvironment(macCatalyst)
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return nil
        #endif
    }

    private func resolveSecurityScopedBookmark(_ data: Data) -> URL? {
        #if targetEnvironment(macCatalyst)
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        #else
        return nil
        #endif
    }

    private func persistWorkspaceBookmark(for url: URL) {
        guard let bookmark = securityScopedBookmark(for: url) else { return }
        sessionDefaults.set(bookmark, forKey: workspaceBookmarkKey)
    }

    private func restoreWorkspace() {
        guard
            let bookmark = sessionDefaults.data(forKey: workspaceBookmarkKey),
            let url = resolveSecurityScopedBookmark(bookmark)
        else { return }
        openWorkspace(url: url)
    }

    private func retainDocumentAccess(to url: URL, for document: EditorDocument) {
        let granted = url.startAccessingSecurityScopedResource()
        if granted {
            documentSecurityScopedURLs.removeValue(forKey: document.id)?.stopAccessingSecurityScopedResource()
            documentSecurityScopedURLs[document.id] = url
        }
        if let bookmark = securityScopedBookmark(for: url) {
            document.securityScopedBookmark = bookmark
        }
    }

    func requestFileAccess(for document: EditorDocument? = nil, folder: Bool = false) {
        if let document { fileAccessRecoveryURL = document.fileURL }
        guard fileAccessRecoveryURL != nil else { return }
        errorMessage = nil
        if folder { isFolderAccessImporterPresented = true }
        else { isFileAccessImporterPresented = true }
    }

    func completeFileAccess(_ result: Result<[URL], Error>, folder: Bool) {
        guard let original = fileAccessRecoveryURL else { return }
        do {
            guard let selected = try result.get().first else { return }
            let selectedPath = selected.standardizedFileURL.path
            let originalPath = original.standardizedFileURL.path
            guard folder ? originalPath.hasPrefix(selectedPath.hasSuffix("/") ? selectedPath : selectedPath + "/")
                : originalPath == selectedPath else {
                errorMessage = preferences.tr("请选择原文件，或包含原文件的文件夹：\n\(original.path)", "Select the original file or a folder containing it:\n\(original.path)")
                return
            }
            let granted = selected.startAccessingSecurityScopedResource()
            defer { if granted { selected.stopAccessingSecurityScopedResource() } }
            // Verify actual access before replacing any stored grant.
            _ = try Data(contentsOf: folder ? original : selected, options: .mappedIfSafe)
            if folder {
                if selected.startAccessingSecurityScopedResource() { authorizedFolderURLs.append(selected) }
                if let bookmark = securityScopedBookmark(for: selected) {
                    authorizedFolderBookmarks[selectedPath] = bookmark
                    if let data = try? JSONEncoder().encode(authorizedFolderBookmarks) {
                        sessionDefaults.set(data, forKey: authorizedFoldersKey)
                    }
                }
                for document in documents where document.fileAccessError != nil {
                    if let path = document.fileURL?.standardizedFileURL.path,
                       path.hasPrefix(selectedPath.hasSuffix("/") ? selectedPath : selectedPath + "/") {
                        reload(document)
                    }
                }
                if !documents.contains(where: { $0.fileURL?.standardizedFileURL == original.standardizedFileURL }) {
                    open(url: original)
                }
            } else {
                open(url: selected)
            }
            persistSession()
        } catch {
            // Cancelling the system panel leaves all groups, tabs and grants intact.
            if (error as NSError).code != CocoaError.userCancelled.rawValue {
                errorMessage = preferences.tr("重新授权失败：\(error.localizedDescription)", "Could not restore file access: \(error.localizedDescription)")
            }
        }
    }

    private func restoreAuthorizedFolders() {
        guard let data = sessionDefaults.data(forKey: authorizedFoldersKey),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data)
        else { return }
        authorizedFolderBookmarks = bookmarks
        for (path, bookmark) in bookmarks {
            guard let url = resolveSecurityScopedBookmark(bookmark),
                  url.startAccessingSecurityScopedResource() else { continue }
            authorizedFolderURLs.append(url)
            if let renewed = securityScopedBookmark(for: url) {
                authorizedFolderBookmarks.removeValue(forKey: path)
                authorizedFolderBookmarks[url.standardizedFileURL.path] = renewed
            }
        }
        if let data = try? JSONEncoder().encode(authorizedFolderBookmarks) {
            sessionDefaults.set(data, forKey: authorizedFoldersKey)
        }
    }

    /// Persist a user-picked folder for Search Files (and other helpers). Safe
    /// for fresh installs: the system folder picker grants access and we keep
    /// an app-scoped bookmark so later launches can resume it.
    func authorizeSearchFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        if !authorizedFolderURLs.contains(where: { $0.standardizedFileURL.path == path }) {
            if url.startAccessingSecurityScopedResource() {
                authorizedFolderURLs.append(url)
            } else {
                authorizedFolderURLs.append(url)
            }
        }
        if let bookmark = securityScopedBookmark(for: url) {
            authorizedFolderBookmarks[path] = bookmark
            if let data = try? JSONEncoder().encode(authorizedFolderBookmarks) {
                sessionDefaults.set(data, forKey: authorizedFoldersKey)
            }
        }
    }

    func removeAuthorizedSearchFolder(_ url: URL) {
        let path = url.standardizedFileURL.path
        if let existing = authorizedFolderURLs.first(where: { $0.standardizedFileURL.path == path }) {
            existing.stopAccessingSecurityScopedResource()
        }
        authorizedFolderURLs.removeAll { $0.standardizedFileURL.path == path }
        authorizedFolderBookmarks.removeValue(forKey: path)
        if let data = try? JSONEncoder().encode(authorizedFolderBookmarks) {
            sessionDefaults.set(data, forKey: authorizedFoldersKey)
        }
    }
}
