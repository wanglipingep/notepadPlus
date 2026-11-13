import XCTest
@testable import NotepadPlusCore

final class WorkspaceFileIdentityTests: XCTestCase {
    func testCanonicalPathCollapsesStandardizedAliases() {
        let a = URL(fileURLWithPath: "/tmp/../tmp/notepad-plus-identity.txt")
        let b = URL(fileURLWithPath: "/tmp/notepad-plus-identity.txt")
        XCTAssertEqual(
            WorkspaceFileIdentity.canonicalPath(for: a),
            WorkspaceFileIdentity.canonicalPath(for: b)
        )
        XCTAssertTrue(WorkspaceFileIdentity.pathsMatch(a, b))
    }

    func testDedupeKeepsOneEntryPerPathPreferringBookmarkAndOpenState() {
        let path = "/Users/demo/Notes/shared.md"
        let weak = WorkspaceSessionDocument(
            id: UUID(), title: "shared.md", scratchContent: nil, path: path,
            securityScopedBookmark: nil, language: "markdown", encoding: "utf8",
            lineEnding: "lf", bookmarks: nil, groupID: nil, isPinned: false, isOpenInTabs: false
        )
        let strong = WorkspaceSessionDocument(
            id: UUID(), title: "shared.md", scratchContent: nil, path: path,
            securityScopedBookmark: Data([1, 2, 3]), language: "markdown", encoding: "utf8",
            lineEnding: "lf", bookmarks: [1], groupID: nil, isPinned: true, isOpenInTabs: true
        )
        let alias = WorkspaceSessionDocument(
            id: UUID(), title: "shared.md", scratchContent: nil,
            path: "/Users/demo/./Notes/shared.md",
            securityScopedBookmark: nil, language: "markdown", encoding: "utf8",
            lineEnding: "lf", bookmarks: nil, groupID: nil, isPinned: false, isOpenInTabs: true
        )
        let untitled = WorkspaceSessionDocument(
            id: UUID(), title: "未命名", scratchContent: "scratch", path: nil,
            securityScopedBookmark: nil, language: "plainText", encoding: "utf8",
            lineEnding: "lf", bookmarks: nil, groupID: nil, isPinned: false, isOpenInTabs: true
        )

        let deduped = WorkspaceFileIdentity.dedupeSessionDocuments([weak, alias, strong, untitled])
        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(deduped.first?.id, strong.id)
        XCTAssertEqual(deduped.last?.id, untitled.id)
        XCTAssertEqual(deduped.first?.securityScopedBookmark, Data([1, 2, 3]))
    }

    func testDedupePreservesConflictingScratchBuffers() {
        let path = "/tmp/conflict.txt"
        let a = WorkspaceSessionDocument(
            id: UUID(), title: "conflict.txt", scratchContent: "alpha", path: path,
            securityScopedBookmark: nil, language: "plainText", encoding: "utf8",
            lineEnding: "lf", bookmarks: nil, groupID: nil, isPinned: false, isOpenInTabs: true
        )
        let b = WorkspaceSessionDocument(
            id: UUID(), title: "conflict.txt", scratchContent: "beta", path: path,
            securityScopedBookmark: nil, language: "plainText", encoding: "utf8",
            lineEnding: "lf", bookmarks: nil, groupID: nil, isPinned: false, isOpenInTabs: true
        )
        let deduped = WorkspaceFileIdentity.dedupeSessionDocuments([a, b])
        XCTAssertEqual(deduped.count, 2)
        XCTAssertEqual(Set(deduped.map(\.id)), Set([a.id, b.id]))
    }

    func testDedupeCollapsesIdenticalPathWhenOnlyOneHasScratch() {
        let path = "/tmp/only-one-scratch.txt"
        let clean = WorkspaceSessionDocument(
            id: UUID(), title: "only-one-scratch.txt", scratchContent: nil, path: path,
            securityScopedBookmark: nil, language: "plainText", encoding: "utf8",
            lineEnding: "lf", bookmarks: nil, groupID: nil, isPinned: false, isOpenInTabs: false
        )
        let dirty = WorkspaceSessionDocument(
            id: UUID(), title: "only-one-scratch.txt", scratchContent: "keep me", path: path,
            securityScopedBookmark: nil, language: "plainText", encoding: "utf8",
            lineEnding: "lf", bookmarks: nil, groupID: nil, isPinned: false, isOpenInTabs: true
        )
        let deduped = WorkspaceFileIdentity.dedupeSessionDocuments([clean, dirty])
        XCTAssertEqual(deduped.count, 1)
        XCTAssertEqual(deduped.first?.id, dirty.id)
        XCTAssertEqual(deduped.first?.scratchContent, "keep me")
    }
}
