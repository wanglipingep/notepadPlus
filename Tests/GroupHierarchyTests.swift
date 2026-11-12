import XCTest
@testable import NotepadPlusCore

final class GroupHierarchyTests: XCTestCase {
    func testThreeLevelOutlinePreservesSiblingOrderAndFullPath() {
        let root = WorkspaceSessionGroup(id: UUID(), name: "工作", color: "green")
        let child = WorkspaceSessionGroup(id: UUID(), name: "项目", color: nil, parentID: root.id)
        let leaf = WorkspaceSessionGroup(id: UUID(), name: "笔记", color: nil, parentID: child.id)
        let sibling = WorkspaceSessionGroup(id: UUID(), name: "归档", color: nil, parentID: root.id)
        let other = WorkspaceSessionGroup(id: UUID(), name: "个人", color: nil)
        let tree = GroupHierarchy([root, other, child, sibling, leaf])
        XCTAssertEqual(tree.outline.map(\.id), [root.id, child.id, leaf.id, sibling.id, other.id])
        XCTAssertEqual(tree.outline.map(\.depth), [0, 1, 2, 1, 0])
        XCTAssertEqual(tree.path(for: leaf.id), "工作 / 项目 / 笔记")
        XCTAssertEqual(tree.descendants(of: root.id), [child.id, leaf.id, sibling.id])
    }

    func testInvalidParentsAndCyclesRemainVisibleAndCannotHangTraversal() {
        let a = UUID(), b = UUID(), c = UUID()
        let tree = GroupHierarchy([
            .init(id: a, name: "A", color: nil, parentID: b),
            .init(id: b, name: "B", color: nil, parentID: a),
            .init(id: c, name: "C", color: nil, parentID: UUID())
        ])
        XCTAssertEqual(Set(tree.outline.map(\.id)), [a, b, c])
        XCTAssertNil(tree.groups.first(where: { $0.id == a })?.parentID)
        XCTAssertNil(tree.groups.first(where: { $0.id == c })?.parentID)
        XCTAssertEqual(tree.path(for: b), "A / B")
    }

    func testReparentingRejectsSelfAndDescendantsButAllowsRootAndOtherBranches() {
        let a = WorkspaceSessionGroup(id: UUID(), name: "A", color: nil)
        let b = WorkspaceSessionGroup(id: UUID(), name: "B", color: nil, parentID: a.id)
        let c = WorkspaceSessionGroup(id: UUID(), name: "C", color: nil, parentID: b.id)
        let d = WorkspaceSessionGroup(id: UUID(), name: "D", color: nil)
        let tree = GroupHierarchy([a, b, c, d])
        XCTAssertFalse(tree.canMove(a.id, to: a.id))
        XCTAssertFalse(tree.canMove(a.id, to: c.id))
        XCTAssertFalse(tree.canMove(a.id, to: UUID()))
        XCTAssertTrue(tree.canMove(b.id, to: nil))
        XCTAssertTrue(tree.canMove(b.id, to: d.id))
    }

    func testLegacyGroupWithoutParentDecodesAsRootAndHierarchyRoundTrips() throws {
        let id = UUID()
        let oldData = Data("{\"id\":\"\(id)\",\"name\":\"旧分组\",\"color\":\"green\"}".utf8)
        let root = try JSONDecoder().decode(WorkspaceSessionGroup.self, from: oldData)
        XCTAssertNil(root.parentID)
        let child = WorkspaceSessionGroup(id: UUID(), name: "子分组", color: "blue", parentID: id)
        let encoded = try JSONEncoder().encode([root, child])
        XCTAssertEqual(try JSONDecoder().decode([WorkspaceSessionGroup].self, from: encoded), [root, child])
    }

    func testRecoveryRecordRoundTripsAncestorsAndDecodesOlderRecord() throws {
        let root = WorkspaceSessionGroup(id: UUID(), name: "根", color: nil)
        let child = WorkspaceSessionGroup(id: UUID(), name: "中间", color: nil, parentID: root.id)
        let record = ScratchRecoveryRecord(id: UUID(), title: "临时笔记", content: "正文", language: "markdown",
            encoding: "utf8", lineEnding: "lf", groupID: UUID(), groupName: "叶子", groupAncestors: [root, child])
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(ScratchRecoveryRecord.self, from: data).groupAncestors, [root, child])
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "groupAncestors")
        XCTAssertNil(try JSONDecoder().decode(ScratchRecoveryRecord.self, from: JSONSerialization.data(withJSONObject: old)).groupAncestors)
    }
}
