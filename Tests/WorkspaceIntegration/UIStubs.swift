// Only the UIKit-facing collaborators are replaced. The workspace, document,
// persistence and file-reading implementation below use the production sources.
import Foundation
import Combine

final class EditorPreferences {
    var autoSave = false
    func tr(_ chinese: String, _ english: String) -> String { chinese }
}
final class FindReplaceState {
    var focusesReplacement = false
    var focusRequest = UUID()
}
extension Notification.Name {
    static let workspaceWillActivateDocument = Self("qa.workspaceWillActivateDocument")
    static let editorSearchRevealSelection = Self("qa.editorSearchRevealSelection")
    static let editorSearchHighlightsChanged = Self("qa.editorSearchHighlightsChanged")
}
struct SearchSelectionRequest { let documentID: UUID; let selection: NSRange }
struct SearchHighlightRequest { let documentID: UUID; let ranges: [NSRange] }
final class SearchRevealStore {
    static let shared = SearchRevealStore()
    func set(_ selection: NSRange, for documentID: UUID) {}
}
final class ScrollPositionStore {
    static let shared = ScrollPositionStore()
    func remove(for documentID: UUID) {}
}
