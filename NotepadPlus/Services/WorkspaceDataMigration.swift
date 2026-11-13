import Foundation

/// Prevents data loss when the Mac Catalyst sandbox setting / storage root
/// changes across upgrades (Container → Application Support + Preferences).
///
/// Upgrade contract for 文档导航:
/// - Never delete Container or live session / recovery archives.
/// - Live document membership is authoritative (exited files stay exited).
/// - Source may only enrich matching ids (scratch / bookmark / group structure).
/// - Path dedupe must not drop conflicting unsaved buffers.
enum WorkspaceDataMigration {
    private static let migrationFlagKey = "notepad-plus.container-migration.v2"
    private static let sessionKey = "notepad-plus.session.v1"
    private static let snippetsKey = "notepad-plus.snippets.v2"
    private static let clipboardKey = "notepad-plus.clipboard-history.v1"

    /// Call once at process start, before `WorkspaceStore` restores the session.
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        // One-shot only. Re-running every launch used to re-import exited
        // documents from the older Container archive.
        // v2 re-runs once for installs that already completed v1, so the
        // live-membership merge (not richness-by-doc-count) is applied; still
        // never deletes archives or live documents.
        if defaults.bool(forKey: migrationFlagKey) { return }
        let legacyV1Key = "notepad-plus.container-migration.v1"

        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let containerRoot = home
            .appendingPathComponent("Library/Containers/com.wanglp.notepadplus/Data/Library", isDirectory: true)
        let containerAS = containerRoot
            .appendingPathComponent("Application Support/NotepadPlus", isDirectory: true)
        let containerPrefs = containerRoot
            .appendingPathComponent("Preferences/com.wanglp.notepadplus.plist", isDirectory: false)

        let liveAS = (fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true))
            .appendingPathComponent("NotepadPlus", isDirectory: true)

        // 1) Merge session files (Container → live Application Support).
        mergeSessionArchives(
            from: containerAS.appendingPathComponent("WorkspaceSession", isDirectory: true),
            into: liveAS.appendingPathComponent("WorkspaceSession", isDirectory: true),
            defaults: defaults,
            fileManager: fm
        )

        // 2) Copy scratch recovery documents that are missing live.
        mergeRecoveryDirectory(
            from: containerAS.appendingPathComponent("TemporaryDocumentRecovery", isDirectory: true),
            into: liveAS.appendingPathComponent("TemporaryDocumentRecovery", isDirectory: true),
            fileManager: fm
        )

        // 3) Prefer richer UserDefaults blobs from the sandboxed preferences plist.
        if let containerDefaults = UserDefaults(suiteName: nil),
           let plistData = try? Data(contentsOf: containerPrefs),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
            mergeDefaultsKey(sessionKey, from: plist, into: defaults)
            mergeDefaultsKey(sessionKey + ".backup", from: plist, into: defaults)
            mergeDefaultsKey(snippetsKey, from: plist, into: defaults)
            mergeDefaultsKey(clipboardKey, from: plist, into: defaults)
            // Also try reading via CFPreferences-style access through a temporary defaults object.
            _ = containerDefaults
        }

        // Direct read of container prefs into defaults when keys are richer.
        if let plistData = try? Data(contentsOf: containerPrefs),
           let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] {
            for key in [sessionKey, sessionKey + ".backup", snippetsKey, clipboardKey,
                        "notepad-plus.authorized-folders.v1", "notepad-plus.recent-files.v1",
                        "notepad-plus.recent-bookmarks.v2"] {
                mergeDefaultsKey(key, from: plist, into: defaults)
            }
        }

        defaults.set(true, forKey: migrationFlagKey)
        defaults.set(true, forKey: legacyV1Key)
        defaults.synchronize()
    }

    // MARK: Session merge

    private static func mergeSessionArchives(
        from sourceDir: URL,
        into liveDir: URL,
        defaults: UserDefaults,
        fileManager fm: FileManager
    ) {
        let sourcePrimary = sourceDir.appendingPathComponent("session.json")
        let sourceBackup = sourceDir.appendingPathComponent("session.backup.json")
        let livePrimary = liveDir.appendingPathComponent("session.json")
        let liveBackup = liveDir.appendingPathComponent("session.backup.json")

        let candidates: [(URL, Data)] = [sourcePrimary, sourceBackup].compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  (try? JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: data)) != nil
            else { return nil }
            return (url, data)
        }
        guard !candidates.isEmpty else { return }

        try? fm.createDirectory(at: liveDir, withIntermediateDirectories: true)

        let bestSource = candidates.max(by: { groupRichness(of: $0.1) < groupRichness(of: $1.1) })!.1
        let liveData = (try? Data(contentsOf: livePrimary))
            ?? defaults.data(forKey: sessionKey)

        if let liveData {
            // Live membership is authoritative (exited docs must stay gone).
            // Only enrich groups / fill missing scratch on matching IDs.
            if let merged = mergeSessions(live: liveData, source: bestSource) {
                // Keep a stamped backup of pre-merge live for forensics.
                let stamped = liveDir.appendingPathComponent(
                    "session.pre-container-merge-\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).json"
                )
                try? liveData.write(to: stamped, options: .atomic)
                try? liveData.write(to: liveBackup, options: .atomic)
                defaults.set(liveData, forKey: sessionKey + ".backup")
                try? merged.write(to: livePrimary, options: .atomic)
                defaults.set(merged, forKey: sessionKey)
            }
        } else {
            try? bestSource.write(to: livePrimary, options: .atomic)
            defaults.set(bestSource, forKey: sessionKey)
        }
    }

    /// Group-structure richness only — never prefer a session merely because
    /// it lists more documents (that resurrected exited files).
    private static func groupRichness(of data: Data) -> Int {
        guard let session = try? JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: data) else {
            return -1
        }
        let groups = session.groups ?? []
        let withParent = groups.filter { $0.parentID != nil }.count
        return groups.count * 5 + withParent * 20
    }

    /// Merge groups from source into live. Document membership follows **live**
    /// only (source may enrich scratch/bookmark on the same id). Same-name
    /// siblings under the same parent collapse so recovered Container groups
    /// do not duplicate.
    private static func mergeSessions(live: Data, source: Data) -> Data? {
        guard let liveSession = try? JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: live),
              let sourceSession = try? JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: source)
        else { return nil }

        var groupsByID: [UUID: WorkspaceSessionGroup] = [:]
        for group in liveSession.groups ?? [] {
            groupsByID[group.id] = group
        }

        // sourceID → liveID when we collapse a same-name sibling.
        var groupIDRemap: [UUID: UUID] = [:]
        for group in sourceSession.groups ?? [] {
            if let existing = groupsByID[group.id] {
                if existing.parentID == nil, group.parentID != nil {
                    groupsByID[group.id] = group
                }
                continue
            }
            if let twin = groupsByID.values.first(where: {
                $0.name == group.name && $0.parentID == group.parentID
            }) {
                groupIDRemap[group.id] = twin.id
                if twin.parentID == nil, group.parentID != nil {
                    groupsByID[twin.id] = WorkspaceSessionGroup(
                        id: twin.id, name: twin.name, color: group.color ?? twin.color, parentID: group.parentID
                    )
                }
                continue
            }
            // Remap parent if the parent itself was remapped.
            let remappedParent = group.parentID.flatMap { groupIDRemap[$0] ?? $0 }
            if let twin = groupsByID.values.first(where: {
                $0.name == group.name && $0.parentID == remappedParent
            }) {
                groupIDRemap[group.id] = twin.id
                continue
            }
            groupsByID[group.id] = WorkspaceSessionGroup(
                id: group.id,
                name: group.name,
                color: group.color,
                parentID: remappedParent
            )
        }

        func remapGroupID(_ id: UUID?) -> UUID? {
            guard let id else { return nil }
            return groupIDRemap[id] ?? id
        }

        let sourceByID = Dictionary(uniqueKeysWithValues: sourceSession.documents.map { ($0.id, $0) })
        var orderedDocs: [WorkspaceSessionDocument] = []
        for liveDoc in liveSession.documents {
            let sourceDoc = sourceByID[liveDoc.id]
            let enrichedScratch = liveDoc.scratchContent ?? sourceDoc?.scratchContent
            let enrichedBookmark = liveDoc.securityScopedBookmark ?? sourceDoc?.securityScopedBookmark
            orderedDocs.append(WorkspaceSessionDocument(
                id: liveDoc.id,
                title: liveDoc.title,
                scratchContent: enrichedScratch,
                path: liveDoc.path ?? sourceDoc?.path,
                securityScopedBookmark: enrichedBookmark,
                language: liveDoc.language ?? sourceDoc?.language,
                encoding: liveDoc.encoding ?? sourceDoc?.encoding,
                lineEnding: liveDoc.lineEnding ?? sourceDoc?.lineEnding,
                bookmarks: liveDoc.bookmarks ?? sourceDoc?.bookmarks,
                groupID: remapGroupID(liveDoc.groupID) ?? remapGroupID(sourceDoc?.groupID),
                isPinned: liveDoc.isPinned ?? sourceDoc?.isPinned,
                isOpenInTabs: liveDoc.isOpenInTabs ?? sourceDoc?.isOpenInTabs
            ))
        }
        orderedDocs = WorkspaceFileIdentity.dedupeSessionDocuments(orderedDocs)

        var orderedGroups = (liveSession.groups ?? []).compactMap { groupsByID[$0.id] }
        var seenGroupIDs = Set(orderedGroups.map(\.id))
        for group in sourceSession.groups ?? [] {
            let id = groupIDRemap[group.id] ?? group.id
            guard seenGroupIDs.insert(id).inserted, let g = groupsByID[id] else { continue }
            orderedGroups.append(g)
        }
        for group in groupsByID.values where seenGroupIDs.insert(group.id).inserted {
            orderedGroups.append(group)
        }

        let merged = WorkspaceSessionSnapshot(
            documents: orderedDocs,
            activeID: liveSession.activeID ?? sourceSession.activeID,
            groups: orderedGroups,
            selectedGroupID: remapGroupID(liveSession.selectedGroupID)
                ?? remapGroupID(sourceSession.selectedGroupID)
        )
        return try? JSONEncoder().encode(merged)
    }

    private static func mergeRecoveryDirectory(from source: URL, into live: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: source.path) else { return }
        try? fm.createDirectory(at: live, withIntermediateDirectories: true)
        guard let items = try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) else { return }
        for item in items where item.pathExtension == "json" {
            let dest = live.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) {
                try? fm.copyItem(at: item, to: dest)
            }
        }
    }

    private static func mergeDefaultsKey(_ key: String, from plist: [String: Any], into defaults: UserDefaults) {
        guard let value = plist[key] else { return }
        if let data = value as? Data {
            let existing = defaults.data(forKey: key)
            if key.hasPrefix(sessionKey) {
                // Never replace a live session blob just because the container
                // copy lists more documents — that resurrected exited files.
                if existing == nil {
                    defaults.set(data, forKey: key)
                } else if let merged = mergeSessions(live: existing!, source: data) {
                    defaults.set(merged, forKey: key)
                }
            } else if existing == nil || (existing?.count ?? 0) < data.count {
                defaults.set(data, forKey: key)
            }
        } else if defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
    }
}
