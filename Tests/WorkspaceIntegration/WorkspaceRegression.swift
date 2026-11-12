import Foundation

@main
struct WorkspaceRegression {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notepadplus-model-qa-\(UUID())")
        let suite = "com.notepadplus.model-qa.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let key = "notepad-plus.session.v1"
        let groupID = UUID()
        let ids = [UUID(), UUID()]
        let fileURLs = [root.appendingPathComponent("任务.txt"), root.appendingPathComponent("计划.txt")]
        let bookmark = Data([0, 255, 3])
        let entries = ids.enumerated().map { index, id in
            WorkspaceSessionDocument(
                id: id, title: fileURLs[index].lastPathComponent, scratchContent: nil,
                path: fileURLs[index].path, securityScopedBookmark: bookmark,
                language: "future-language", encoding: "utf8", lineEnding: "lf",
                bookmarks: [2], groupID: groupID, isPinned: true
            )
        }
        let session = WorkspaceSessionSnapshot(
            documents: entries, activeID: ids[1],
            groups: [WorkspaceSessionGroup(id: groupID, name: "原分组", color: "future-color")],
            selectedGroupID: groupID
        )
        defaults.set(try JSONEncoder().encode(session), forKey: key)
        struct RecentFixture: Codable { let path: String; let bookmark: Data? }
        defaults.set(try JSONEncoder().encode(fileURLs.map { RecentFixture(path: $0.path, bookmark: bookmark) }),
                     forKey: "notepad-plus.recent-bookmarks.v2")
        let recovery = root.appendingPathComponent("recovery/TemporaryDocumentRecovery")
        let workspace = WorkspaceStore(preferences: EditorPreferences(), defaults: defaults, recoveryDirectory: recovery)
        precondition(workspace.documentGroups.first?.name == "原分组")
        precondition(workspace.documentGroups.first?.color == .green)
        precondition(workspace.documents.map(\.id) == ids)
        precondition(workspace.documents.allSatisfy { $0.groupID == groupID && $0.fileAccessError != nil && !$0.isDirty && $0.isPinned })
        precondition(workspace.activeDocumentID == ids[1])
        workspace.open(url: fileURLs[0])
        let recents = try JSONDecoder().decode([RecentFixture].self,
                                               from: defaults.data(forKey: "notepad-plus.recent-bookmarks.v2")!)
        precondition(recents.allSatisfy { $0.bookmark == bookmark })
        workspace.flushPendingChanges()
        let restored = try JSONDecoder().decode(WorkspaceSessionSnapshot.self, from: defaults.data(forKey: key)!)
        precondition(restored.documents.allSatisfy { $0.securityScopedBookmark == bookmark && $0.groupID == groupID && $0.bookmarks == [2] })
        do {
            try workspace.save(workspace.documents[0])
            fatalError("An unloaded placeholder must never be saved")
        } catch {
            precondition(!FileManager.default.fileExists(atPath: fileURLs[0].path))
        }
        print("PASS: inaccessible grouped files and old bookmarks survive restore/save; placeholder cannot overwrite disk")

        for (index, url) in fileURLs.enumerated() { try "原文\(index)\n第二行".write(to: url, atomically: true, encoding: .utf8) }
        workspace.requestFileAccess(for: workspace.documents[0], folder: true)
        workspace.completeFileAccess(.success([root]), folder: true)
        precondition(workspace.documents.map(\.id) == ids)
        precondition(workspace.documents.allSatisfy { $0.groupID == groupID && $0.fileAccessError == nil && !$0.isDirty && $0.bookmarks == [2] })
        precondition(workspace.documents[0].content == "原文0\n第二行")
        let reopened = WorkspaceStore(preferences: EditorPreferences(), defaults: defaults, recoveryDirectory: recovery)
        precondition(reopened.documents.map(\.id) == ids && reopened.documentGroups.first?.id == groupID)
        precondition(reopened.documents[1].content == "原文1\n第二行")
        print("PASS: folder recovery reloads all matching files in their original groups and survives relaunch")

        reopened.requestFileAccess(for: reopened.documents[0])
        let beforeCancel = defaults.data(forKey: key)
        reopened.completeFileAccess(.failure(CocoaError(.userCancelled)), folder: false)
        precondition(defaults.data(forKey: key) == beforeCancel)
        reopened.completeFileAccess(.success([fileURLs[1]]), folder: false)
        precondition(reopened.documents[0].fileURL == fileURLs[0])
        precondition(reopened.documents[0].groupID == groupID && reopened.documents.count == 2)
        print("PASS: cancellation and selecting another file preserve the original records")

        let deniedSuite = suite + ".denied"
        let deniedDefaults = UserDefaults(suiteName: deniedSuite)!
        defer { deniedDefaults.removePersistentDomain(forName: deniedSuite) }
        let deniedURL = root.appendingPathComponent("权限拒绝.txt")
        try "不能被空文档覆盖的原文".write(to: deniedURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: deniedURL.path)
        let deniedID = UUID()
        let deniedEntry = WorkspaceSessionDocument(
            id: deniedID, title: deniedURL.lastPathComponent, scratchContent: nil, path: deniedURL.path,
            securityScopedBookmark: bookmark, language: "plainText", encoding: "utf8", lineEnding: "lf",
            bookmarks: [3], groupID: groupID, isPinned: true
        )
        let deniedSession = WorkspaceSessionSnapshot(documents: [deniedEntry], activeID: deniedID,
                                                     groups: session.groups, selectedGroupID: groupID)
        deniedDefaults.set(try JSONEncoder().encode(deniedSession), forKey: key)
        let deniedWorkspace = WorkspaceStore(preferences: EditorPreferences(), defaults: deniedDefaults,
                                             recoveryDirectory: root.appendingPathComponent("denied/TemporaryDocumentRecovery"))
        precondition(deniedWorkspace.documents.count == 1 && deniedWorkspace.documents[0].fileAccessError != nil)
        do { try deniedWorkspace.save(deniedWorkspace.documents[0]); fatalError("Denied file was saved") } catch {}
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: deniedURL.path)
        let preservedSource = try String(contentsOf: deniedURL, encoding: .utf8)
        precondition(preservedSource == "不能被空文档覆盖的原文")
        deniedWorkspace.requestFileAccess(for: deniedWorkspace.documents[0])
        deniedWorkspace.completeFileAccess(.success([deniedURL]), folder: false)
        precondition(deniedWorkspace.documents[0].id == deniedID && deniedWorkspace.documents[0].groupID == groupID)
        precondition(deniedWorkspace.documents[0].content == "不能被空文档覆盖的原文" && deniedWorkspace.documents[0].fileAccessError == nil)
        print("PASS: real filesystem permission denial preserves source bytes; single-file recovery keeps document/group identity")

        let corruptSuite = suite + ".corrupt"
        let corruptDefaults = UserDefaults(suiteName: corruptSuite)!
        defer { corruptDefaults.removePersistentDomain(forName: corruptSuite) }
        let corrupt = Data("{broken session".utf8)
        corruptDefaults.set(corrupt, forKey: key)
        let blocked = WorkspaceStore(preferences: EditorPreferences(), defaults: corruptDefaults,
                                     recoveryDirectory: root.appendingPathComponent("corrupt/TemporaryDocumentRecovery"))
        blocked.newDocument()
        blocked.flushPendingChanges()
        precondition(corruptDefaults.data(forKey: key) == corrupt)
        precondition(blocked.errorMessage != nil)
        print("PASS: startup/new/flush after decoding failure do not overwrite the original session")
        let groupSuite = suite + ".hierarchy"
        let groupDefaults = UserDefaults(suiteName: groupSuite)!
        defer { groupDefaults.removePersistentDomain(forName: groupSuite) }
        let groupRecovery = root.appendingPathComponent("groups/TemporaryDocumentRecovery")
        let grouped = WorkspaceStore(preferences: EditorPreferences(), defaults: groupDefaults, recoveryDirectory: groupRecovery)
        let top = grouped.addDocumentGroup(named: "顶级")!
        let middle = grouped.addDocumentGroup(named: "二级", parentID: top.id)!
        let leaf = grouped.addDocumentGroup(named: "三级", parentID: middle.id)!
        let note = grouped.newDocument()
        note.content = "三级分组的临时文档"
        precondition(note.groupID == leaf.id)
        precondition(grouped.addDocumentGroup(named: "非法父级", parentID: UUID()) == nil)
        grouped.moveDocumentGroup(top, to: leaf.id)
        precondition(grouped.documentGroups.first(where: { $0.id == top.id })?.parentID == nil)
        grouped.flushPendingChanges()
        let groupRestart = WorkspaceStore(preferences: EditorPreferences(), defaults: groupDefaults, recoveryDirectory: groupRecovery)
        precondition(groupRestart.groupHierarchy.path(for: leaf.id) == "顶级 / 二级 / 三级")
        precondition(groupRestart.documents.first(where: { $0.id == note.id })?.groupID == leaf.id)
        let direct = groupRestart.newDocument()
        groupRestart.assign(direct, to: middle)
        groupRestart.removeDocumentGroup(middle)
        precondition(groupRestart.documentGroups.first(where: { $0.id == leaf.id })?.parentID == top.id)
        precondition(direct.groupID == top.id)
        precondition(groupRestart.documents.first(where: { $0.id == note.id })?.groupID == leaf.id)
        print("PASS: three-level groups survive relaunch, reject cycles, and deletion retains children/documents")

        let vaultSuite = suite + ".vault"
        let vaultDefaults = UserDefaults(suiteName: vaultSuite)!
        defer { vaultDefaults.removePersistentDomain(forName: vaultSuite) }
        let vaultOnly = WorkspaceStore(preferences: EditorPreferences(), defaults: vaultDefaults, recoveryDirectory: groupRecovery)
        precondition(vaultOnly.documents.first(where: { $0.id == note.id })?.content == "三级分组的临时文档")
        precondition(vaultOnly.groupHierarchy.path(for: leaf.id) == "顶级 / 三级")
        print("PASS: standalone scratch recovery restores group ancestors without a saved session")
        print("Workspace integration: 7 regression scenarios passed (isolated temporary fixtures; no user data)")
    }
}
