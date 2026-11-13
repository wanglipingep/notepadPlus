import Foundation

/// Canonical file identity for workspace session membership.
/// Used to prevent the same on-disk file appearing as multiple documents.
enum WorkspaceFileIdentity {
    /// Stable path key for open/session matching. Resolves symlinks when the
    /// file is reachable so `/var` vs `/private/var` aliases collapse.
    static func canonicalPath(for url: URL) -> String {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath().standardizedFileURL.path
        }
        return standardized.path
    }

    static func pathsMatch(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs else { return false }
        return canonicalPath(for: lhs) == canonicalPath(for: rhs)
    }

    /// Keep one session entry per file path. Prefer the entry that still has
    /// scratch content, a bookmark, or is marked open-in-tabs. Never drops
    /// untitled (path-less) documents.
    static func dedupeSessionDocuments(_ documents: [WorkspaceSessionDocument]) -> [WorkspaceSessionDocument] {
        var result: [WorkspaceSessionDocument] = []
        var indexByPath: [String: Int] = [:]

        for document in documents {
            guard let path = document.path, !path.isEmpty else {
                result.append(document)
                continue
            }
            let key = canonicalPath(for: URL(fileURLWithPath: path))
            if let existingIndex = indexByPath[key] {
                let existing = result[existingIndex]
                let candidateScratch = document.scratchContent
                let existingScratch = existing.scratchContent
                // Conflicting unsaved buffers: keep both rather than drop either.
                if let candidateScratch, !candidateScratch.isEmpty,
                   let existingScratch, !existingScratch.isEmpty,
                   candidateScratch != existingScratch {
                    result.append(document)
                    continue
                }
                if prefer(document, over: existing) {
                    result[existingIndex] = document
                }
            } else {
                indexByPath[key] = result.count
                result.append(document)
            }
        }
        return result
    }

    private static func prefer(_ candidate: WorkspaceSessionDocument, over existing: WorkspaceSessionDocument) -> Bool {
        let candidateScratch = !(candidate.scratchContent?.isEmpty ?? true)
        let existingScratch = !(existing.scratchContent?.isEmpty ?? true)
        if candidateScratch != existingScratch { return candidateScratch }

        let candidateBookmark = candidate.securityScopedBookmark != nil
        let existingBookmark = existing.securityScopedBookmark != nil
        if candidateBookmark != existingBookmark { return candidateBookmark }

        let candidateOpen = candidate.isOpenInTabs ?? true
        let existingOpen = existing.isOpenInTabs ?? true
        if candidateOpen != existingOpen { return candidateOpen }

        return false
    }
}
