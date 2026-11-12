import XCTest
@testable import NotepadPlusCore

final class WorkspaceSessionTests: XCTestCase {
    private let sessionKey = "notepad-plus.session.v1"
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    private var archive: WorkspaceSessionArchive!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("notepadplus-session-qa-\(UUID())")
        suite = "com.notepadplus.tests.\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        archive = WorkspaceSessionArchive(directoryURL: directory, defaults: defaults, key: sessionKey)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func fixture(title: String = "任务.txt") -> WorkspaceSessionSnapshot {
        let group = WorkspaceSessionGroup(id: UUID(), name: "工作资料", color: "green")
        let document = WorkspaceSessionDocument(
            id: UUID(), title: title, scratchContent: nil,
            path: "/unmounted-volume/任务.txt", securityScopedBookmark: Data([0, 255, 2, 3]),
            language: "plainText", encoding: "utf8", lineEnding: "lf",
            bookmarks: [2, 9], groupID: group.id, isPinned: true
        )
        return WorkspaceSessionSnapshot(documents: [document], activeID: document.id, groups: [group], selectedGroupID: group.id)
    }

    func testLegacyDefaultsMigrationKeepsGroupsUnavailablePathsAndOriginalBookmarkBytes() throws {
        let session = fixture()
        let legacy = try JSONEncoder().encode(session)
        defaults.set(legacy, forKey: sessionKey)
        XCTAssertEqual(try archive.load(), session)
        try archive.save(session)
        XCTAssertEqual(try archive.load(), session)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("session.before-migration.json")), legacy)
        XCTAssertEqual(try archive.load()?.documents.first?.securityScopedBookmark, Data([0, 255, 2, 3]))
    }

    func testUnknownDisplayEnumsAndMissingOlderFieldsDoNotDiscardSession() throws {
        let session = fixture()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        var documents = try XCTUnwrap(json["documents"] as? [[String: Any]])
        documents[0]["language"] = "future-language"
        documents[0].removeValue(forKey: "encoding")
        documents[0].removeValue(forKey: "isPinned")
        var groups = try XCTUnwrap(json["groups"] as? [[String: Any]])
        groups[0]["color"] = "future-color"
        json["documents"] = documents
        json["groups"] = groups
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: sessionKey)
        let restored = try XCTUnwrap(archive.load())
        XCTAssertEqual(restored.groups?.first?.name, "工作资料")
        XCTAssertEqual(restored.documents.first?.groupID, session.groups?.first?.id)
        XCTAssertEqual(restored.documents.first?.language, "future-language")
        XCTAssertNil(restored.documents.first?.encoding)
    }

    func testCorruptPrimaryAndDefaultsFallBackToPreviousGroupsWithoutDestroyingEvidence() throws {
        let previous = fixture()
        try archive.save(previous)
        try archive.save(fixture(title: "新版.txt"))
        let corrupt = Data("{broken".utf8)
        try corrupt.write(to: directory.appendingPathComponent("session.json"))
        defaults.set(corrupt, forKey: sessionKey)
        XCTAssertEqual(try archive.load(), previous)
        let evidence = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("unreadable") }
        XCTAssertFalse(evidence.isEmpty)
        XCTAssertEqual(try Data(contentsOf: evidence[0]), corrupt)
        try archive.save(previous)
        XCTAssertEqual(try archive.load(), previous)
    }

    func testFullyCorruptLegacySessionThrowsInsteadOfReturningEmpty() throws {
        let corrupt = Data("{not-a-session".utf8)
        defaults.set(corrupt, forKey: sessionKey)
        XCTAssertThrowsError(try archive.load())
        XCTAssertEqual(defaults.data(forKey: sessionKey), corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("session.json").path))
    }

    func testEmptyNamedGroupSurvivesRelaunch() throws {
        let group = WorkspaceSessionGroup(id: UUID(), name: "尚未添加文件", color: nil)
        let session = WorkspaceSessionSnapshot(documents: [], activeID: nil, groups: [group], selectedGroupID: group.id)
        try archive.save(session)
        let reopened = WorkspaceSessionArchive(directoryURL: directory, defaults: defaults, key: sessionKey)
        XCTAssertEqual(try reopened.load(), session)
    }

    func testFailedAtomicWriteLeavesLegacySessionUntouched() throws {
        let original = try JSONEncoder().encode(fixture())
        defaults.set(original, forKey: sessionKey)
        try Data("directory-is-a-file".utf8).write(to: directory)
        XCTAssertThrowsError(try archive.save(fixture(title: "不应保存.txt")))
        XCTAssertEqual(defaults.data(forKey: sessionKey), original)
    }

    func testMalformedEntryDoesNotSilentlyDropOtherFilesOrGroups() throws {
        let session = fixture()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        var documents = try XCTUnwrap(json["documents"] as? [[String: Any]])
        documents.append(["id": UUID().uuidString, "title": "损坏的记录"])
        json["documents"] = documents
        let original = try JSONSerialization.data(withJSONObject: json)
        defaults.set(original, forKey: sessionKey)
        XCTAssertThrowsError(try archive.load())
        XCTAssertEqual(defaults.data(forKey: sessionKey), original)
    }
}
