import Foundation

/// Stable sibling order, with invalid parents/cycles repaired to root groups.
struct GroupHierarchy {
    struct Entry: Identifiable, Equatable { let id: UUID; let depth: Int }
    let groups: [WorkspaceSessionGroup]

    init(_ groups: [WorkspaceSessionGroup]) {
        let ids = Set(groups.map(\.id))
        var repaired = groups
        var parents = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.parentID) })
        for index in repaired.indices {
            let id = repaired[index].id
            var seen: Set<UUID> = [id]
            var next = repaired[index].parentID
            var invalid = false
            while let current = next {
                guard ids.contains(current), seen.insert(current).inserted else { invalid = true; break }
                next = parents[current] ?? nil
            }
            if invalid {
                repaired[index].parentID = nil
                parents[id] = .some(nil)
            }
        }
        self.groups = repaired
    }

    func ancestors(of id: UUID) -> [UUID] {
        let parents = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.parentID) })
        var result: [UUID] = []
        var next = parents[id] ?? nil
        while let parent = next { result.append(parent); next = parents[parent] ?? nil }
        return result
    }

    func descendants(of id: UUID) -> Set<UUID> {
        var result: Set<UUID> = []
        var pending = [id]
        while let parent = pending.popLast() {
            for group in groups where group.parentID == parent && result.insert(group.id).inserted {
                pending.append(group.id)
            }
        }
        return result
    }

    var outline: [Entry] {
        let children = Dictionary(grouping: groups, by: \.parentID)
        var pending = (children[nil] ?? []).reversed().map { Entry(id: $0.id, depth: 0) }
        var result: [Entry] = []
        while let entry = pending.popLast() {
            result.append(entry)
            pending.append(contentsOf: (children[entry.id] ?? []).reversed().map { Entry(id: $0.id, depth: entry.depth + 1) })
        }
        return result
    }

    func path(for id: UUID) -> String {
        let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        return (ancestors(of: id).reversed() + [id]).compactMap { names[$0] }.joined(separator: " / ")
    }

    func canMove(_ id: UUID, to parentID: UUID?) -> Bool {
        guard groups.contains(where: { $0.id == id }) else { return false }
        guard let parentID else { return true }
        return groups.contains(where: { $0.id == parentID }) && parentID != id && !descendants(of: id).contains(parentID)
    }
}

struct MarkdownScrollPosition: Equatable {
    var sourceLine: Double = 1
    var progress: Double = 0

    init(sourceLine: Double = 1, progress: Double = 0) {
        self.sourceLine = sourceLine.isFinite ? max(1, sourceLine) : 1
        self.progress = progress.isFinite ? min(1, max(0, progress)) : 0
    }
}
