import SwiftUI
import UIKit

private enum EditorPerformance {
    /// Syntax colouring, bracket matching and JSON folding are deliberately
    /// deferred for very large documents. TextKit can display and select the
    /// raw text immediately, which is the same responsiveness users expect
    /// from Notepad++ when opening a large file.
    static let deferredProcessingUTF16Length = LargeFilePolicy.largeUTF16Threshold
    /// Scintilla's Select All only stores two offsets and repaints the visible
    /// lines. Asking UITextView to select a longer range forces TextKit to
    /// build selection geometry for every glyph, which is the hitch users
    /// still feel on ordinary documents well below the large-file threshold.
    static let virtualSelectAllUTF16Length = LargeFilePolicy.virtualSelectAllUTF16Threshold
}

struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    let contentRevision: UInt
    @Binding var selection: NSRange

    let documentID: UUID
    let scrollOffset: CGPoint
    let onScrollOffsetChange: (CGPoint) -> Void
    let language: SyntaxLanguage
    @ObservedObject var preferences: EditorPreferences
    let onTextChange: () -> Void
    let onJSONFormattingError: (String) -> Void
    var markdownScrollPosition: MarkdownScrollPosition? = nil
    var onMarkdownScroll: ((MarkdownScrollPosition) -> Void)? = nil
    /// Used by the editor context menu checkmark for Markdown preview.
    var isMarkdownPreviewPresented: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIView(_ textView: LineNumberTextView, coordinator: Coordinator) {
        // Tab switches can dismantle the UIKit view before SwiftUI delivers
        // another update pass. Capture the final viewport while the old
        // document is still the coordinator's parent.
        coordinator.saveCurrentScrollOffset()
    }

    func makeUIView(context: Context) -> LineNumberTextView {
        let textView = LineNumberTextView()
        #if targetEnvironment(macCatalyst)
        textView.closeCommandIsEnabled = preferences.shortcut(for: .closeDocument) == ShortcutAction.closeDocument.defaultBinding
        textView.onCloseDocumentCommand = {
            NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.closeActiveDocument)
        }
        textView.onFindCommand = {
            NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.find)
        }
        textView.onReplaceCommand = {
            NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.replace)
        }
        #endif
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardDismissMode = .interactive
        textView.allowsEditingTextAttributes = false
        // Configure TextKit's non-contiguous layout before inserting the
        // document.  UIKit otherwise starts laying out the entire buffer
        // with its default contiguous mode; on tens-of-megabytes files that
        // makes the initial assignment (and the first Command-A) block the
        // main thread before the editor can become interactive.
        configure(textView)
        // Assigning the buffer moves UITextView's caret to the end and can
        // scroll there before the saved line anchor is applied. Hold the
        // viewport until restoration finishes.
        textView.beginPreservingViewport(.restore)
        textView.text = text
        textView.invalidateLineNumberCache()
        // `configure(_:)` enables JSON folding before UIKit receives the
        // document text.  That first scan therefore sees an empty buffer;
        // schedule a second scan after assigning the text so the gutter has
        // fold regions on the initial open (especially for large JSON files,
        // where the scan runs asynchronously).
        if textView.jsonFoldingEnabled {
            textView.updateJSONFoldRegions()
        }
        textView.selectedRange = selection
        context.coordinator.markConfigurationApplied(for: textView)
        context.coordinator.markContentApplied(contentRevision)
        // UIKit emits an initial zero-offset callback while the replacement
        // view is being laid out. Keep that transient value from overwriting
        // the document's saved viewport before restoration runs.
        context.coordinator.beginScrollRestoration()
        context.coordinator.attach(to: textView, documentID: documentID)
        context.coordinator.scheduleInitialHighlight(textView)
        if let pending = SearchRevealStore.shared.consume(for: documentID) {
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                let safe = NSIntersectionRange(
                    pending,
                    NSRange(location: 0, length: textView.textStorage.length)
                )
                textView.selectedRange = safe
                textView.scrollRangeToVisible(safe)
            }
        }
        DispatchQueue.main.async { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator, coordinator.documentID == documentID else { return }
            coordinator.restoreScrollOffset(scrollOffset, in: textView)
        }
        return textView
    }

    func updateUIView(_ textView: LineNumberTextView, context: Context) {
        #if targetEnvironment(macCatalyst)
        textView.closeCommandIsEnabled = preferences.shortcut(for: .closeDocument) == ShortcutAction.closeDocument.defaultBinding
        #endif
        let documentChanged = context.coordinator.documentID != documentID
        if documentChanged {
            // SwiftUI may replace the bound document before UIKit emits its
            // final scroll callback. Save the outgoing viewport explicitly
            // while the coordinator still points at the previous document.
            context.coordinator.saveCurrentScrollOffset()
        }
        context.coordinator.parent = self
        // Language changes do not require a font/layout reconfiguration, so
        // they can bypass `configure(_:)`. Keep the fold engine in sync when
        // switching a tab between JSON and a normal text language.
        let foldStyle = Self.foldStyle(for: language, utf16Length: text.utf16.count)
        if textView.codeFoldStyle != foldStyle {
            textView.codeFoldStyle = foldStyle
        }
        if documentChanged {
            context.coordinator.documentID = documentID
            context.coordinator.beginScrollRestoration()
        }

        let receivedExternalText = context.coordinator.needsContentSync(
            for: contentRevision,
            documentChanged: documentChanged
        )
        if receivedExternalText {
            // A content revision change is the explicit signal that the
            // binding changed. Internal UIKit edits are already in sync and
            // are marked by the coordinator, so no whole-document equality
            // check is needed here.
            let previous = textView.selectedRange
            let lineNumberTextView = textView as? LineNumberTextView
            lineNumberTextView?.beginPreservingViewport(.externalReload)
            lineNumberTextView?.clearVirtualSelection(notify: false)
            lineNumberTextView?.clearMultiSelections()
            textView.text = text
            textView.invalidateLineNumberCache()
            textView.updateJSONFoldRegions()
            textView.selectedRange = clamped(previous, for: textView.text)
            context.coordinator.markContentApplied(contentRevision)
            lineNumberTextView?.reapplyViewportAnchor()
            DispatchQueue.main.async { [weak lineNumberTextView] in
                lineNumberTextView?.reapplyViewportAnchor()
                lineNumberTextView?.endPreservingViewport(.externalReload)
            }
        }
        // For very large documents LineNumberTextView uses a virtual whole-
        // document selection. Assigning the complete range to TextKit forces
        // it to lay out every glyph just to paint the selection, which can
        // make Command-A appear to hang. Keep the virtual range in the
        // document binding while preserving the lightweight native caret.
        let hasVirtualSelection = (textView as? LineNumberTextView)?.virtualSelectionRange == selection
        if textView.selectedRange != selection, !hasVirtualSelection, textView.markedTextRange == nil {
            let targetSelection = clamped(selection, for: textView.text)
            textView.selectedRange = targetSelection
            // A programmatic navigation (for example Go To Line, bookmark
            // navigation, or a workspace search result) updates the binding
            // while UIKit is still showing the old viewport.  Previously we
            // deliberately skipped this scroll to avoid stale-selection
            // jumps, which also meant Go To Line could report the new line in
            // the status bar while the editor remained thousands of lines
            // away.  User taps do not enter this branch because the native
            // selection has already been published by UITextView, and a tab
            // switch is restored explicitly below.  Deferring one run-loop
            // turn lets TextKit finish applying the range before scrolling.
            if !documentChanged {
                DispatchQueue.main.async { [weak textView] in
                    guard let textView,
                          textView.selectedRange == targetSelection else { return }
                    textView.scrollRangeToVisible(targetSelection)
                }
            }
        }

        // Selection changes (including Command-A) publish through SwiftUI and
        // call updateUIView. Reapplying font/container metrics on every one of
        // those updates forces TextKit to relayout the whole document, which
        // is very noticeable for large files. Only configure when an editor
        // preference or appearance actually changed.
        if context.coordinator.configurationNeedsUpdate(for: textView) {
            configure(textView)
            context.coordinator.markConfigurationApplied(for: textView)
        }
        context.coordinator.refreshHighlighting(textView, force: receivedExternalText)
        if documentChanged {
            let targetOffset = scrollOffset
            DispatchQueue.main.async { [weak textView, weak coordinator = context.coordinator] in
                guard let textView, let coordinator, coordinator.documentID == documentID else { return }
                coordinator.restoreScrollOffset(targetOffset, in: textView)
            }
        }
    }

    private func configure(_ textView: LineNumberTextView) {
        // Allow TextKit to lay out only the visible portions of large
        // documents. This materially reduces the cost of a full-document
        // selection (Command+A) and of subsequent caret updates.
        textView.layoutManager.allowsNonContiguousLayout = true
        let palette = EditorPalette.resolve(
            appearance: preferences.appearance,
            traits: textView.traitCollection,
            customBackgroundHex: preferences.customBackgroundHex,
            customForegroundHex: preferences.customForegroundHex
        )
        textView.editorPalette = palette
        textView.backgroundColor = palette.background
        textView.tintColor = UIColor(red: 0.36, green: 0.72, blue: 0.28, alpha: 1)
        textView.font = UIFont(
            name: preferences.fontName,
            size: CGFloat(preferences.fontSize)
        ) ?? UIFont.monospacedSystemFont(
            ofSize: CGFloat(preferences.fontSize),
            weight: .regular
        )
        textView.showLineNumbers = preferences.showLineNumbers
        textView.showWhitespace = preferences.showWhitespace
        let utf16Length = (textView.text as NSString?)?.length ?? text.utf16.count
        let tier = LargeFilePolicy.tier(byteCount: 0, utf16Length: utf16Length)
        textView.codeFoldStyle = Self.foldStyle(for: language, utf16Length: utf16Length, tier: tier)
        textView.textContainerInset = UIEdgeInsets(
            top: 12,
            left: preferences.showLineNumbers ? textView.gutterWidth + 8 : 10,
            bottom: 24,
            right: 12
        )

        // Mirror Notepad++ large-file shedding: huge buffers force unwrap so
        // TextKit does not pay for wrap layout on every edit.
        let wordWrap = preferences.wordWrap && !LargeFilePolicy.disablesWordWrap(tier)
        if wordWrap {
            textView.textContainer.widthTracksTextView = true
            textView.textContainer.size = CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            textView.alwaysBounceHorizontal = false
            textView.showsHorizontalScrollIndicator = false
        } else {
            textView.textContainer.widthTracksTextView = false
            textView.textContainer.size = CGSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.alwaysBounceHorizontal = true
            textView.showsHorizontalScrollIndicator = true
        }
    }

    private static func foldStyle(
        for language: SyntaxLanguage,
        utf16Length: Int,
        tier: LargeFilePolicy.Tier? = nil
    ) -> LineNumberTextView.CodeFoldStyle {
        let resolved = tier ?? LargeFilePolicy.tier(byteCount: 0, utf16Length: utf16Length)
        if LargeFilePolicy.disablesJSONFolding(resolved) { return .none }
        if language == .json || language == .jsonc { return .json }
        if BraceFolding.supports(language) { return .braces }
        return .none
    }

    private func clamped(_ range: NSRange, for string: String) -> NSRange {
        let length = (string as NSString).length
        let location = min(max(range.location, 0), length)
        let selectionLength = min(max(range.length, 0), length - location)
        return NSRange(location: location, length: selectionLength)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: CodeEditorView
        private weak var textView: UITextView?
        private var commandObserver: NSObjectProtocol?
        private var documentActivationObserver: NSObjectProtocol?
        // Content revisions are cheaper and safer than comparing the entire
        // String on every SwiftUI selection update. The old text comparison
        // made Command-A on a large non-JSON file perform another O(n) pass
        // immediately after selecting it.
        private var lastHighlightedContentRevision: UInt?
        private var lastLanguage: SyntaxLanguage?
        private var lastFontSize: Double?
        private var lastFontName: String?
        private var lastAppearance: EditorAppearance?
        private var lastCustomBackground: String?
        private var lastCustomForeground: String?
        private weak var wheelZoomGesture: UIPanGestureRecognizer?
        private weak var columnDragGesture: UIPanGestureRecognizer?
        private var columnAnchor = 0
        private var isUpdatingColumnSelection = false
        private var isUpdatingMultiSelection = false
        private var columnSelectionConversion: DispatchWorkItem?
        private var highlightWorkItem: DispatchWorkItem?
        private var scrollPollTimer: Timer?
        fileprivate var documentID: UUID?
        private var isRestoringScrollOffset = false
        private var scrollRestorationToken = 0
        private var isSelectingAll = false
        private var configuredAppearance: EditorAppearance?
        private var configuredFontName: String?
        private var configuredFontSize: Double?
        private var configuredShowLineNumbers: Bool?
        private var configuredShowWhitespace: Bool?
        private var configuredWordWrap: Bool?
        private var configuredLineSpacing: Double?
        private var configuredTextAlignment: EditorTextAlignment?
        private var configuredCustomBackground: String?
        private var configuredCustomForeground: String?
        private var configuredUserInterfaceStyle: UIUserInterfaceStyle?
        private var appliedContentRevision: UInt?
        private var internalContentChangePending = false
        private var bracketHighlightRanges: [NSRange] = []
        private var searchHighlightRanges: [NSRange] = []
        private var currentSearchHighlightRange: NSRange?
        private var searchSelectionObserver: NSObjectProtocol?
        private var searchHighlightsObserver: NSObjectProtocol?
        private var searchReplacementObserver: NSObjectProtocol?
        private var externalReloadObserver: NSObjectProtocol?
        private var isApplyingSearchSelection = false
        private var forceSearchReveal = false

        init(parent: CodeEditorView) {
            self.parent = parent
        }

        func configurationNeedsUpdate(for textView: UITextView) -> Bool {
            configuredAppearance != parent.preferences.appearance
                || configuredFontName != parent.preferences.fontName
                || configuredFontSize != parent.preferences.fontSize
                || configuredShowLineNumbers != parent.preferences.showLineNumbers
                || configuredShowWhitespace != parent.preferences.showWhitespace
                || configuredWordWrap != parent.preferences.wordWrap
                || configuredLineSpacing != parent.preferences.lineSpacing
                || configuredTextAlignment != parent.preferences.textAlignment
                || configuredCustomBackground != parent.preferences.customBackgroundHex
                || configuredCustomForeground != parent.preferences.customForegroundHex
                || configuredUserInterfaceStyle != textView.traitCollection.userInterfaceStyle
        }

        func markConfigurationApplied(for textView: UITextView) {
            configuredAppearance = parent.preferences.appearance
            configuredFontName = parent.preferences.fontName
            configuredFontSize = parent.preferences.fontSize
            configuredShowLineNumbers = parent.preferences.showLineNumbers
            configuredShowWhitespace = parent.preferences.showWhitespace
            configuredWordWrap = parent.preferences.wordWrap
            configuredLineSpacing = parent.preferences.lineSpacing
            configuredTextAlignment = parent.preferences.textAlignment
            configuredCustomBackground = parent.preferences.customBackgroundHex
            configuredCustomForeground = parent.preferences.customForegroundHex
            configuredUserInterfaceStyle = textView.traitCollection.userInterfaceStyle
        }

        func markContentApplied(_ revision: UInt) {
            appliedContentRevision = revision
        }

        func needsContentSync(for revision: UInt, documentChanged: Bool) -> Bool {
            let revisionChanged = appliedContentRevision != revision
            guard revisionChanged else { return false }
            if documentChanged {
                internalContentChangePending = false
                return true
            }
            if internalContentChangePending {
                // Only skip when UIKit already shows the bound text. An
                // external reload bumps the revision while the text view may
                // still hold the previous buffer — skipping would leave stale
                // text on screen and later write it back into the model.
                if let textView, textView.text == parent.text {
                    internalContentChangePending = false
                    appliedContentRevision = revision
                    return false
                }
                internalContentChangePending = false
                return true
            }
            return true
        }

        deinit {
            if let markdownScrollObserver { NotificationCenter.default.removeObserver(markdownScrollObserver) }
            if let commandObserver { NotificationCenter.default.removeObserver(commandObserver) }
            if let documentActivationObserver { NotificationCenter.default.removeObserver(documentActivationObserver) }
            if let searchSelectionObserver { NotificationCenter.default.removeObserver(searchSelectionObserver) }
            if let searchHighlightsObserver { NotificationCenter.default.removeObserver(searchHighlightsObserver) }
            if let searchReplacementObserver { NotificationCenter.default.removeObserver(searchReplacementObserver) }
            if let externalReloadObserver { NotificationCenter.default.removeObserver(externalReloadObserver) }
            columnSelectionConversion?.cancel()
            highlightWorkItem?.cancel()
            scrollPollTimer?.invalidate()
        }

        func attach(to textView: LineNumberTextView, documentID: UUID) {
            self.textView = textView
            self.documentID = documentID
            if let markdownScrollObserver { NotificationCenter.default.removeObserver(markdownScrollObserver) }
            markdownScrollObserver = NotificationCenter.default.addObserver(
                forName: .markdownPreviewDidScroll, object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let request = notification.object as? MarkdownScrollRequest,
                      request.documentID == self.documentID, self.parent.onMarkdownScroll != nil else { return }
                self.applyMarkdownScroll(request.position)
            }
            textView.onVirtualSelectionChanged = { [weak self] selection in
                guard let self else { return }
                // A virtual selection is intentionally not reflected by
                // UITextView.selectedRange. Publish it through the same
                // document binding used by normal selections so SwiftUI and
                // the status bar remain in sync without forcing TextKit to
                // lay out the entire buffer.
                if let selection {
                    self.parent.selection = selection
                } else if let textView = self.textView {
                    self.parent.selection = textView.selectedRange
                }
            }
            textView.contentOffsetDidChange = { [weak self] offset in
                self?.textViewDidScroll(to: offset)
            }
            // Some Mac Catalyst trackpad/wheel paths update the native scroll
            // view without delivering the delegate callback. Polling at a
            // modest rate keeps the per-document viewport current without
            // tying it to SwiftUI's render cycle.
            scrollPollTimer?.invalidate()
            scrollPollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.pollScrollOffset()
            }
            textView.columnTextDidChange = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.textViewDidChange(textView)
            }
            textView.onJSONFoldingChanged = { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.refreshHighlighting(textView, force: true)
            }
            textView.panGestureRecognizer.addTarget(self, action: #selector(handleEditorPan(_:)))
            commandObserver = NotificationCenter.default.addObserver(
                forName: .editorNativeAction,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let action = notification.object as? EditorNativeAction else { return }
                self?.perform(action)
            }
            // WorkspaceStore announces tab activation before changing its
            // active document. This is the last guaranteed moment when this
            // coordinator still owns the outgoing document and viewport.
            documentActivationObserver = NotificationCenter.default.addObserver(
                forName: .workspaceWillActivateDocument,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let outgoingID = notification.object as? UUID,
                      outgoingID == self.documentID
                else { return }
                self.saveCurrentScrollOffset()
            }

            searchSelectionObserver = NotificationCenter.default.addObserver(
                forName: .editorSearchRevealSelection,
                object: nil,
                queue: .main
            ) { [weak self, weak textView] notification in
                guard let self, let textView,
                      let request = notification.object as? SearchSelectionRequest,
                      request.documentID == self.documentID
                else { return }
                let fullRange = NSRange(location: 0, length: textView.textStorage.length)
                let safe = NSIntersectionRange(request.selection, fullRange)
                SearchRevealStore.shared.set(safe, for: request.documentID)
                _ = SearchRevealStore.shared.consume(for: request.documentID)
                self.currentSearchHighlightRange = safe
                self.isApplyingSearchSelection = true
                self.forceSearchReveal = true
                self.applySearchHighlights(to: textView)
                DispatchQueue.main.async {
                    textView.selectedRange = safe
                    if let editor = textView as? LineNumberTextView {
                        editor.revealRangeIgnoringViewportHold(safe)
                    } else {
                        textView.scrollRangeToVisible(safe)
                    }
                    self.forceSearchReveal = false
                    self.isApplyingSearchSelection = false
                    self.applySearchHighlights(to: textView)
                }
            }
            searchHighlightsObserver = NotificationCenter.default.addObserver(
                forName: .editorSearchHighlightsChanged,
                object: nil,
                queue: .main
            ) { [weak self, weak textView] notification in
                guard let self, let textView,
                      let request = notification.object as? SearchHighlightRequest,
                      request.documentID == self.documentID
                else { return }
                self.searchHighlightRanges = request.ranges
                if let current = request.currentRange {
                    self.currentSearchHighlightRange = current
                }
                self.applySearchHighlights(to: textView)
            }
            externalReloadObserver = NotificationCenter.default.addObserver(
                forName: .editorExternalContentReloaded,
                object: nil,
                queue: .main
            ) { [weak self, weak textView] notification in
                guard let self, let textView,
                      let documentID = notification.object as? UUID,
                      documentID == self.documentID
                else { return }
                // Force the bridge to accept the next revision even if a
                // stale internal-edit marker was still pending.
                self.internalContentChangePending = false
                self.appliedContentRevision = nil
                let text = self.parent.text
                let editor = textView as? LineNumberTextView
                editor?.beginPreservingViewport(.externalReload)
                editor?.clearVirtualSelection(notify: false)
                editor?.clearMultiSelections()
                textView.text = text
                editor?.invalidateLineNumberCache()
                editor?.updateJSONFoldRegions()
                self.markContentApplied(self.parent.contentRevision)
                self.refreshHighlighting(textView, force: true)
                editor?.reapplyViewportAnchor()
                DispatchQueue.main.async { [weak editor] in
                    editor?.reapplyViewportAnchor()
                    editor?.endPreservingViewport(.externalReload)
                }
            }
            searchReplacementObserver = NotificationCenter.default.addObserver(
                forName: .editorSearchReplaceText,
                object: nil,
                queue: .main
            ) { [weak self, weak textView] notification in
                guard let self, let textView,
                      let request = notification.object as? SearchReplacementRequest,
                      request.documentID == self.documentID,
                      textView.text == request.originalText else { return }
                textView.applySearchReplacement(request.text, selection: request.selection)
            }

            let wheelZoom = UIPanGestureRecognizer(target: self, action: #selector(handleWheelZoom(_:)))
            wheelZoom.allowedScrollTypesMask = .continuous
            wheelZoom.cancelsTouchesInView = false
            wheelZoom.delegate = self
            textView.addGestureRecognizer(wheelZoom)
            wheelZoomGesture = wheelZoom

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            textView.addGestureRecognizer(pinch)

            let columnDrag = UIPanGestureRecognizer(target: self, action: #selector(handleColumnDrag(_:)))
            columnDrag.minimumNumberOfTouches = 1
            columnDrag.maximumNumberOfTouches = 1
            columnDrag.cancelsTouchesInView = true
            columnDrag.delaysTouchesBegan = false
            columnDrag.delegate = self
            textView.addGestureRecognizer(columnDrag)
            textView.panGestureRecognizer.require(toFail: columnDrag)
            columnDragGesture = columnDrag

        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer === wheelZoomGesture {
                return gestureRecognizer.modifierFlags.contains(.control)
            }
            if gestureRecognizer === columnDragGesture {
                return gestureRecognizer.modifierFlags.contains(.alternate) || parent.preferences.columnMode
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer !== columnDragGesture && otherGestureRecognizer !== columnDragGesture
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === columnDragGesture
        }

        @objc private func handleWheelZoom(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let delta = recognizer.translation(in: view).y
            guard abs(delta) >= 8 else { return }
            parent.preferences.fontSize = min(40, max(9, parent.preferences.fontSize + (delta < 0 ? 1 : -1)))
            recognizer.setTranslation(.zero, in: view)
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .changed, abs(recognizer.scale - 1) > 0.08 else { return }
            parent.preferences.fontSize = min(40, max(9, parent.preferences.fontSize + (recognizer.scale > 1 ? 1 : -1)))
            recognizer.scale = 1
        }

        @objc private func handleEditorPan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed || recognizer.state == .ended,
                  let textView else { return }
            textViewDidScroll(to: textView.contentOffset)
        }

        @objc private func handleColumnDrag(_ recognizer: UIPanGestureRecognizer) {
            guard let textView = recognizer.view as? LineNumberTextView else { return }
            var point = recognizer.location(in: textView)
            point.x = max(point.x, textView.textContainerInset.left + 1)
            guard let position = textView.closestPosition(to: point) else { return }
            let location = textView.offset(from: textView.beginningOfDocument, to: position)

            if recognizer.state == .began {
                textView.becomeFirstResponder()
                columnAnchor = location
            }

            guard recognizer.state == .began || recognizer.state == .changed || recognizer.state == .ended else {
                return
            }
            let rectangle = RectangularSelectionEngine.selection(
                in: textView.text,
                anchor: columnAnchor,
                head: location
            )
            isUpdatingColumnSelection = true
            textView.setColumnSelection(rectangle)
            if let first = rectangle.ranges.first {
                textView.selectedRange = first
                parent.selection = first
            }
            isUpdatingColumnSelection = false
        }

        private func perform(_ action: EditorNativeAction) {
            guard let textView, textView.isFirstResponder else { return }
            switch action {
            case .undo: textView.undoManager?.undo()
            case .redo: textView.undoManager?.redo()
            case .cut: textView.cut(nil)
            case .copy: textView.copy(nil)
            case .paste: textView.paste(nil)
            case .selectAll:
                // Assigning the range directly avoids UIKit's menu/action
                // traversal and skips the expensive rectangular-selection
                // conversion for large documents.
                isSelectingAll = true
                if let lineNumberTextView = textView as? LineNumberTextView {
                    lineNumberTextView.selectAllFast()
                    parent.selection = lineNumberTextView.selectionForBinding
                } else {
                    textView.selectedRange = TextSelectionEngine.allRange(in: textView.text)
                    parent.selection = textView.selectedRange
                }
                DispatchQueue.main.async { [weak self] in
                    self?.isSelectingAll = false
                }
            case .clearColumnSelection:
                (textView as? LineNumberTextView)?.clearColumnSelection()
            case .selectNextOccurrence:
                if let lineNumberTextView = textView as? LineNumberTextView {
                    isUpdatingMultiSelection = true
                    lineNumberTextView.selectNextOccurrence()
                    parent.selection = lineNumberTextView.selectedRange
                    isUpdatingMultiSelection = false
                }
            case .clearMultiSelections:
                (textView as? LineNumberTextView)?.clearMultiSelections()
            case .deleteJSONValue:
                if let lineNumberTextView = textView as? LineNumberTextView,
                   lineNumberTextView.deleteJSONValue(at: textView.selectedRange) != nil {
                    textViewDidChange(textView)
                }
            case .foldCurrentJSON:
                if let lineNumberTextView = textView as? LineNumberTextView,
                   let line = lineNumberTextView.jsonFoldLine(containing: textView.selectedRange) {
                    lineNumberTextView.toggleJSONFold(at: line)
                }
            case .foldAllJSON:
                (textView as? LineNumberTextView)?.setAllJSONFolds(collapsed: true)
            case .unfoldAllJSON:
                (textView as? LineNumberTextView)?.setAllJSONFolds(collapsed: false)
            case .formatJSON:
                formatJSON(in: textView, range: textView.selectedRange)
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            (textView as? LineNumberTextView)?.invalidateLineNumberCache()
            (textView as? LineNumberTextView)?.updateJSONFoldRegions()
            parent.text = textView.text
            parent.selection = textView.selectedRange
            internalContentChangePending = true
            parent.onTextChange()
            guard textView.markedTextRange == nil else { return }
            scheduleHighlight(for: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            columnSelectionConversion?.cancel()
            if let columnTextView = textView as? LineNumberTextView,
               columnTextView.virtualSelectionRange != nil,
               columnTextView.selectedRange != columnTextView.virtualSelectionRange,
               !isSelectingAll,
               columnTextView.isSelectingAllFast == false {
                // A click, cursor movement, or keyboard navigation exits the
                // virtual whole-document selection. Keep subsequent edits
                // on the native range and publish that range normally.
                // Command-A itself must not take this path: the native caret
                // stays zero-length on purpose while the binding holds the
                // whole document.
                columnTextView.clearVirtualSelection()
            }
            if isApplyingSearchSelection {
                parent.selection = textView.selectedRange
                return
            }
            if isSelectingAll || (textView as? LineNumberTextView)?.isSelectingAllFast == true {
                // Command-A only needs to update the bound range. Do not run
                // bracket matching or rectangular-selection conversion for a
                // selection that spans a large document. The virtual range is
                // the one Scintilla would store; the native caret stays put so
                // TextKit does not lay out the whole buffer.
                parent.selection = (textView as? LineNumberTextView)?.selectionForBinding ?? textView.selectedRange
                return
            }
            if let multiTextView = textView as? LineNumberTextView,
               multiTextView.hasMultiSelections,
               !isUpdatingMultiSelection {
                let current = textView.selectedRange
                let stillInside = multiTextView.multiSelections.contains { NSEqualRanges($0, current) }
                if !stillInside {
                    multiTextView.clearMultiSelections()
                }
            }
            refreshBracketHighlight(textView)
            if !isUpdatingColumnSelection, let columnTextView = textView as? LineNumberTextView {
                columnTextView.clearColumnSelection()
                let linearSelection = textView.selectedRange
                // RectangularSelectionEngine intentionally builds one range
                // per line.  Running it for a whole multi-megabyte document
                // turns Command-A/drag selection into an O(n) allocation
                // storm, so defer column conversion for large buffers.  The
                // explicit Alt-drag path remains available for users who
                // need a rectangular selection there.
                let allowsImplicitColumnConversion = textView.textStorage.length < EditorPerformance.deferredProcessingUTF16Length
                if parent.preferences.columnMode, linearSelection.length > 0, allowsImplicitColumnConversion {
                    let rectangle = RectangularSelectionEngine.selection(
                        in: textView.text,
                        anchor: linearSelection.location,
                        head: NSMaxRange(linearSelection)
                    )
                    if rectangle.ranges.count > 1 {
                        let workItem = DispatchWorkItem { [weak self, weak columnTextView] in
                            guard let self, let columnTextView,
                                  columnTextView.selectedRange == linearSelection
                            else { return }
                            self.isUpdatingColumnSelection = true
                            if let first = rectangle.ranges.first {
                                columnTextView.selectedRange = first
                                self.parent.selection = first
                            }
                            columnTextView.setColumnSelection(rectangle)
                            self.isUpdatingColumnSelection = false
                        }
                        columnSelectionConversion = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
                    }
                }
            }
            if parent.selection != textView.selectedRange {
                parent.selection = textView.selectedRange
            }
        }

        private func refreshBracketHighlight(_ textView: UITextView) {
            let isJSON = parent.language == .json || parent.language == .jsonc
            let tier = LargeFilePolicy.tier(byteCount: 0, utf16Length: textView.textStorage.length)
            if LargeFilePolicy.disablesBracketMatch(tier), !isJSON {
                bracketHighlightRanges.removeAll()
                return
            }
            guard textView.textStorage.length < EditorPerformance.deferredProcessingUTF16Length || isJSON else {
                bracketHighlightRanges.removeAll()
                return
            }
            let palette = EditorPalette.resolve(
                appearance: parent.preferences.appearance,
                traits: textView.traitCollection,
                customBackgroundHex: parent.preferences.customBackgroundHex,
                customForegroundHex: parent.preferences.customForegroundHex
            )
            bracketHighlightRanges = SyntaxHighlighter.highlightMatchingBrackets(
                in: textView,
                selection: textView.selectedRange,
                palette: palette,
                clearing: bracketHighlightRanges
            )
        }

        private func textViewDidScroll(to offset: CGPoint) {
            guard !isRestoringScrollOffset else { return }
            if (textView as? LineNumberTextView)?.preservesViewport == true { return }
            let anchor = (textView as? LineNumberTextView)?.viewportAnchor
            if let lineNumberTextView = textView as? LineNumberTextView {
                lineNumberTextView.rememberContentOffset(offset)
            }
            if let documentID {
                ScrollPositionStore.shared.set(
                    offset,
                    anchorLocation: anchor?.location ?? 0,
                    anchorPixelDelta: anchor?.pixelDelta ?? 0,
                    for: documentID
                )
            }
            parent.onScrollOffsetChange(offset)
            if !isApplyingMarkdownScroll, let textView = textView as? LineNumberTextView, parent.onMarkdownScroll != nil {
                parent.onMarkdownScroll?(textView.markdownViewportPosition())
            }
        }

        private var markdownScrollObserver: NSObjectProtocol?
        private var isApplyingMarkdownScroll = false

        private func applyMarkdownScroll(_ position: MarkdownScrollPosition) {
            guard let textView = textView as? LineNumberTextView else { return }
            markdownScrollGeneration &+= 1
            let token = markdownScrollGeneration
            isApplyingMarkdownScroll = true
            textView.scrollToMarkdownPosition(position)
            parent.onScrollOffsetChange(textView.contentOffset)
            // Keep the suppress flag long enough to cover scrollbar drag
            // events + the 80ms scroll poll, or the editor will echo back and
            // fight the preview while the user is still dragging.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.markdownScrollGeneration == token else { return }
                self.isApplyingMarkdownScroll = false
            }
        }

        private var markdownScrollGeneration: UInt = 0

        private func pollScrollOffset() {
            guard !isRestoringScrollOffset, let textView else { return }
            if (textView as? LineNumberTextView)?.preservesViewport == true { return }
            let liveOffset = liveScrollOffset(for: textView)
            let cachedOffset = (textView as? LineNumberTextView)?.lastKnownContentOffset ?? .zero
            guard liveOffset != cachedOffset else { return }
            textViewDidScroll(to: liveOffset)
        }

        func saveCurrentScrollOffset() {
            guard let textView else { return }
            // Read UIKit's live value at the exact activation boundary. The
            // cached callback value can lag behind wheel scrolling on Mac
            // Catalyst, which caused a tab to restore an older line.
            let liveOffset = liveScrollOffset(for: textView)
            let cachedOffset = (textView as? LineNumberTextView)?.lastKnownContentOffset ?? .zero
            // During a Catalyst tab transition UIKit can briefly report a
            // zero offset for the outgoing view. Preserve the last callback
            // only for that transient all-zero value; otherwise trust the
            // live offset so scrolling upward is saved exactly as requested.
            let offset = liveOffset == .zero && cachedOffset != .zero ? cachedOffset : liveOffset
            let anchor = (textView as? LineNumberTextView)?.viewportAnchor
            if let lineNumberTextView = textView as? LineNumberTextView {
                lineNumberTextView.rememberContentOffset(offset)
            }
            if let documentID {
                ScrollPositionStore.shared.set(
                    offset,
                    anchorLocation: anchor?.location ?? 0,
                    anchorPixelDelta: anchor?.pixelDelta ?? 0,
                    for: documentID
                )
            }
            parent.onScrollOffsetChange(offset)
        }

        private func liveScrollOffset(for textView: UITextView) -> CGPoint {
            // The text view owns the document's logical viewport. Ancestor
            // SwiftUI scroll containers use a different coordinate system;
            // mixing their offsets caused an upward scroll to be replaced by
            // a stale, larger parent offset during tab switches.
            textView.contentOffset
        }

        // UIScrollView delegate callbacks are the reliable scroll signal on
        // Mac Catalyst; overriding contentOffset alone does not fire for all
        // user-driven scrolling paths.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            textViewDidScroll(to: scrollView.contentOffset)
        }

        func beginScrollRestoration() {
            scrollRestorationToken &+= 1
            isRestoringScrollOffset = true
        }

        func restoreScrollOffset(_ offset: CGPoint, in textView: UITextView) {
            scrollRestorationToken &+= 1
            let token = scrollRestorationToken
            isRestoringScrollOffset = true
            // The workspace value is the document's source of truth. Keep a
            // callback-independent cache as a fallback, but never let an old
            // (often zero) cache overwrite a newer offset supplied by the
            // workspace. This is what previously caused repeated tab switches
            // to restore the document at line 1.
            let stored = documentID.flatMap { ScrollPositionStore.shared.position(for: $0) }
            let requestedOffset: CGPoint
            if offset != .zero {
                // The workspace receives the live scroll callbacks and is
                // authoritative once it has a non-zero viewport. A stale
                // global cache must not win over this value.
                requestedOffset = offset
            } else if let stored {
                // Keep the cache only as a fallback during the brief interval
                // before SwiftUI publishes the document's first offset.
                requestedOffset = CGPoint(x: stored.x, y: stored.y)
            } else {
                requestedOffset = .zero
            }
            let anchorLocation = stored?.anchorLocation ?? 0
            let anchorPixelDelta = CGFloat(stored?.anchorPixelDelta ?? 0)
            if let documentID {
                ScrollPositionStore.shared.set(
                    requestedOffset,
                    anchorLocation: anchorLocation,
                    anchorPixelDelta: anchorPixelDelta,
                    for: documentID
                )
            }

            // Text assignment and syntax highlighting can change the content
            // size after the first layout pass. Reapply the saved *line*, not
            // only the raw point: TextKit's first content size is an estimate
            // and clamping the point to that estimate pins the document at
            // the top or the end.
            func apply() {
                guard token == scrollRestorationToken else { return }
                textView.layoutIfNeeded()
                if let editor = textView as? LineNumberTextView {
                    editor.restoreViewport(
                        anchorLocation: anchorLocation,
                        anchorPixelDelta: anchorPixelDelta,
                        fallback: requestedOffset
                    )
                } else {
                    textView.setContentOffset(requestedOffset, animated: false)
                }
            }

            apply()
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView, token == self.scrollRestorationToken else { return }
                apply()
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView, token == self.scrollRestorationToken else { return }
                    apply()
                    self.isRestoringScrollOffset = false
                    if let editor = textView as? LineNumberTextView {
                        editor.endPreservingViewport(.restore)
                        // Keep a short post-restore guard: the first mouse
                        // click after a tab switch still hits EOF until
                        // TextKit lays out the visible band.
                        editor.armPostRestoreInteractionGuard()
                    }
                    if let position = self.parent.markdownScrollPosition {
                        self.applyMarkdownScroll(position)
                    } else if let editor = textView as? LineNumberTextView {
                        self.parent.onMarkdownScroll?(editor.markdownViewportPosition())
                    }
                }
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            if let columnTextView = textView as? LineNumberTextView,
               columnTextView.hasColumnSelection {
                columnTextView.replaceColumnSelections(with: text)
                return false
            }
            if let multiTextView = textView as? LineNumberTextView,
               multiTextView.hasMultiSelections {
                multiTextView.replaceMultiSelections(with: text)
                return false
            }
            guard text == "\t" else { return true }
            let spaces = String(repeating: " ", count: max(parent.preferences.tabWidth, 1))
            if let swiftRange = Range(range, in: textView.text) {
                var updatedText = textView.text ?? ""
                updatedText.replaceSubrange(swiftRange, with: spaces)
                textView.text = updatedText
                textView.selectedRange = NSRange(location: range.location + spaces.utf16.count, length: 0)
                textViewDidChange(textView)
            }
            return false
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            let hasSelection = range.length > 0
            let transformActions: [UIAction] = [
                transformationAction(
                    .uppercase,
                    title: "转换为大写",
                    imageName: "textformat.size.larger",
                    range: range,
                    textView: textView,
                    isEnabled: hasSelection
                ),
                transformationAction(
                    .lowercase,
                    title: "转换为小写",
                    imageName: "textformat.size.smaller",
                    range: range,
                    textView: textView,
                    isEnabled: hasSelection
                ),
                transformationAction(
                    .capitalize,
                    title: "单词首字母大写",
                    imageName: "textformat",
                    range: range,
                    textView: textView,
                    isEnabled: hasSelection
                )
            ]

            let transformMenu = UIMenu(
                title: "大小写转换",
                image: UIImage(systemName: "textformat"),
                children: transformActions
            )
            let columnAction = UIAction(
                title: parent.preferences.columnMode ? "关闭列模式" : "开启列模式",
                image: UIImage(systemName: parent.preferences.columnMode
                    ? "rectangle.split.3x1.fill"
                    : "rectangle.split.3x1"),
                state: parent.preferences.columnMode ? .on : .off
            ) { [weak self, weak textView] _ in
                guard let self else { return }
                self.parent.preferences.columnMode.toggle()
                if !self.parent.preferences.columnMode {
                    (textView as? LineNumberTextView)?.clearColumnSelection()
                }
            }
            let commonTools = UIMenu(
                title: "常用编辑工具",
                options: .displayInline,
                children: [transformMenu, columnAction]
            )
            let lineActions: [UIMenuElement] = [
                UIAction(title: "合并行", image: UIImage(systemName: "arrow.right.and.line.vertical.and.arrow.left")) { _ in
                    NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.editLine(.joinWithNext))
                },
                UIAction(title: "删除空行", image: UIImage(systemName: "line.3.horizontal.decrease")) { _ in
                    NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.editLine(.removeEmptyLines))
                }
            ]
            let jsonPanelActions: [UIMenuElement] = [
                UIAction(title: "JSONPath 查询", image: UIImage(systemName: "point.3.connected.trianglepath.dotted")) { _ in
                    NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.showJSONPath)
                },
                UIAction(title: "JSON 错误定位", image: UIImage(systemName: "exclamationmark.triangle")) { _ in
                    NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.validateJSON)
                }
            ]
            let markdownStyleActions: [UIMenuElement] = MarkdownPreviewStyle.allCases.map { style in
                UIAction(
                    title: style.title,
                    image: UIImage(systemName: style.symbolName),
                    state: parent.preferences.markdownPreviewStyle == style ? .on : .off
                ) { [weak self] _ in
                    guard let self else { return }
                    self.parent.preferences.markdownPreviewStyle = style
                    if !self.parent.isMarkdownPreviewPresented {
                        NotificationCenter.default.post(
                            name: .desktopCommand,
                            object: DesktopCommand.toggleMarkdownPreview
                        )
                    }
                }
            }
            let markdownMenu = UIMenu(
                title: "Markdown 预览",
                image: UIImage(systemName: "text.document"),
                children: [
                    UIAction(
                        title: parent.isMarkdownPreviewPresented ? "隐藏预览" : "显示预览",
                        image: UIImage(systemName: parent.isMarkdownPreviewPresented
                            ? "rectangle.righthalf.inset.filled"
                            : "eye"),
                        state: parent.isMarkdownPreviewPresented ? .on : .off
                    ) { _ in
                        NotificationCenter.default.post(
                            name: .desktopCommand,
                            object: DesktopCommand.toggleMarkdownPreview
                        )
                    },
                    UIMenu(
                        title: "预览风格",
                        image: UIImage(systemName: "paintpalette"),
                        options: .singleSelection,
                        children: markdownStyleActions
                    )
                ]
            )
            var children: [UIMenuElement] = [
                commonTools,
                markdownMenu,
                UIMenu(title: "行操作", image: UIImage(systemName: "text.line.first.and.arrowtriangle.forward"), options: .displayInline, children: lineActions),
                UIMenu(title: "JSON", image: UIImage(systemName: "curlybraces"), options: .displayInline, children: jsonPanelActions)
            ]
            // `editMenuForTextIn` supplies the insertion point for a
            // right-click with no selection (length == 0).  Do not replace
            // that point with a stale `selectedRange`: on Catalyst that made
            // “折叠当前括号” resolve to the document's root object and hide
            // everything through EOF.  Fall back only when UIKit reports an
            // out-of-bounds range.
            let textLength = (textView.text as NSString).length
            let menuRangeIsValid = range.location >= 0
                && range.location <= textLength
                && range.length >= 0
                && NSMaxRange(range) <= textLength
            let jsonRange = menuRangeIsValid ? range : textView.selectedRange
            if parent.language == .json || parent.language == .jsonc {
                let currentFoldLine = (textView as? LineNumberTextView)?.jsonFoldLine(containing: jsonRange)
                let currentFoldIsCollapsed = currentFoldLine.map {
                    (textView as? LineNumberTextView)?.isJSONFoldCollapsed(at: $0) == true
                } ?? false
                let jsonActions: [UIMenuElement] = [
                    UIAction(
                        title: "打开 JSON 工具箱",
                        image: UIImage(systemName: "wrench.and.screwdriver")
                    ) { _ in
                        NotificationCenter.default.post(name: .desktopCommand, object: DesktopCommand.showJSONTools)
                    },
                    UIAction(
                        title: "删除当前 JSON 值",
                        image: UIImage(systemName: "trash"),
                        attributes: JSONValueEditing.deletionRange(in: textView.text, selection: jsonRange) == nil
                            ? [.disabled] : [.destructive]
                    ) { [weak self, weak textView] _ in
                        guard let self, let textView,
                              let lineNumberTextView = textView as? LineNumberTextView,
                              lineNumberTextView.deleteJSONValue(at: jsonRange) != nil else { return }
                        self.textViewDidChange(textView)
                    },
                    UIAction(
                        title: currentFoldIsCollapsed ? "展开当前括号" : "折叠当前括号",
                        image: UIImage(systemName: currentFoldIsCollapsed ? "plus" : "minus"),
                        attributes: currentFoldLine == nil ? [.disabled] : []
                    ) { [weak textView] _ in
                        guard let textView,
                              let lineNumberTextView = textView as? LineNumberTextView,
                              let currentFoldLine else { return }
                        lineNumberTextView.toggleJSONFold(at: currentFoldLine)
                    },
                    UIAction(
                        title: "折叠全部 JSON",
                        image: UIImage(systemName: "chevron.down.2")
                    ) { [weak textView] _ in
                        (textView as? LineNumberTextView)?.setAllJSONFolds(collapsed: true)
                    },
                    UIAction(
                        title: "展开全部 JSON",
                        image: UIImage(systemName: "chevron.up.2")
                    ) { [weak textView] _ in
                        (textView as? LineNumberTextView)?.setAllJSONFolds(collapsed: false)
                    },
                    UIAction(
                        title: "格式化 JSON",
                        image: UIImage(systemName: "curlybraces")
                    ) { [weak self, weak textView] _ in
                        guard let self, let textView else { return }
                        self.formatJSON(in: textView, range: jsonRange)
                    }
                ]
                children.append(UIMenu(title: "JSON 工具", image: UIImage(systemName: "curlybraces"), children: jsonActions))
            } else {
                children.append(UIAction(
                    title: "格式化 JSON",
                    image: UIImage(systemName: "curlybraces")
                ) { [weak self, weak textView] _ in
                    guard let self, let textView else { return }
                    self.formatJSON(in: textView, range: jsonRange)
                })
            }
            return UIMenu(children: children + suggestedActions)
        }

        private func formatJSON(in textView: UITextView, range: NSRange) {
            let isJSONDocument = parent.language == .json || parent.language == .jsonc
            let source = textView.text as NSString
            let selectedRange = range.length > 0
                ? range
                : (isJSONDocument ? NSRange(location: 0, length: source.length) : NSRange(location: 0, length: 0))
            let safeRange = NSIntersectionRange(selectedRange, NSRange(location: 0, length: source.length))
            guard safeRange.length > 0 else { return }

            do {
                let original = source.substring(with: safeRange)
                let result = try JSONFormatter.format(original)
                guard result.text != original else { return }
                guard
                    let start = textView.position(from: textView.beginningOfDocument, offset: safeRange.location),
                    let end = textView.position(from: start, offset: safeRange.length),
                    let textRange = textView.textRange(from: start, to: end)
                else { return }
                textView.replace(textRange, withText: result.text)
                textView.selectedRange = NSRange(
                    location: safeRange.location,
                    length: (result.text as NSString).length
                )
                textViewDidChange(textView)
            } catch {
                // In ordinary text, the command is intentionally a no-op when
                // the selected content is not JSON. JSON documents still show
                // a useful diagnostic for malformed whole-document input.
                if isJSONDocument {
                    parent.onJSONFormattingError(error.localizedDescription)
                }
            }
        }

        private func transformationAction(
            _ transformation: TextTransformation,
            title: String,
            imageName: String,
            range: NSRange,
            textView: UITextView,
            isEnabled: Bool
        ) -> UIAction {
            UIAction(
                title: title,
                image: UIImage(systemName: imageName),
                attributes: isEnabled ? [] : [.disabled]
            ) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.apply(transformation, to: range, in: textView)
            }
        }

        private func apply(
            _ transformation: TextTransformation,
            to range: NSRange,
            in textView: UITextView
        ) {
            let source = textView.text as NSString
            let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: source.length))
            guard safeRange.length > 0 else { return }
            let replacement = transformation.apply(to: source.substring(with: safeRange))
            guard
                let start = textView.position(from: textView.beginningOfDocument, offset: safeRange.location),
                let end = textView.position(from: start, offset: safeRange.length),
                let textRange = textView.textRange(from: start, to: end)
            else { return }
            textView.replace(textRange, withText: replacement)
            textView.selectedRange = NSRange(
                location: safeRange.location,
                length: (replacement as NSString).length
            )
            textViewDidChange(textView)
        }

        func refreshHighlighting(_ textView: UITextView, force: Bool = false) {
            let styleChanged = lastLanguage != parent.language
                || lastFontSize != parent.preferences.fontSize
                || lastFontName != parent.preferences.fontName
                || lastAppearance != parent.preferences.appearance
                || lastCustomBackground != parent.preferences.customBackgroundHex
                || lastCustomForeground != parent.preferences.customForegroundHex
            if force || styleChanged {
                highlightWorkItem?.cancel()
                highlightWorkItem = nil
                if force { lastHighlightedContentRevision = nil }
                scheduleInitialHighlight(textView)
            }
            // Text edits already schedule highlighting from textViewDidChange.
            // Comparing the entire document string on every SwiftUI update
            // (including selection/Command-A updates) is O(n) and caused a
            // second large-document pause even when no text changed.
        }

        private func scheduleHighlight(for textView: UITextView) {
            highlightWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, textView.markedTextRange == nil else { return }
                self.highlightWorkItem = nil
                self.highlightNow(textView)
            }
            highlightWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: workItem)
        }

        func scheduleInitialHighlight(_ textView: UITextView) {
            highlightWorkItem?.cancel()
            let delay: TimeInterval = textView.textStorage.length >= EditorPerformance.deferredProcessingUTF16Length
                ? 0.35
                : 0
            let workItem = DispatchWorkItem { [weak self, weak textView] in
                guard let self, let textView, textView.markedTextRange == nil else { return }
                self.highlightWorkItem = nil
                self.highlightNow(textView)
            }
            highlightWorkItem = workItem
            if delay == 0 {
                DispatchQueue.main.async(execute: workItem)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
            }
        }

        func highlightNow(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            let editor = textView as? LineNumberTextView
            let isLargeDocument = textView.textStorage.length >= EditorPerformance.deferredProcessingUTF16Length
            let appearance = parent.preferences.appearance
            guard
                lastHighlightedContentRevision != parent.contentRevision
                    || lastLanguage != parent.language
                    || lastFontSize != parent.preferences.fontSize
                || lastFontName != parent.preferences.fontName
                || lastAppearance != appearance
                || lastCustomBackground != parent.preferences.customBackgroundHex
                || lastCustomForeground != parent.preferences.customForegroundHex
            else { return }

            // Paragraph styling invalidates TextKit's estimated content size.
            // Without holding the line anchor, that first layout pass scrolls
            // the caret — often the end of the buffer — into view.
            editor?.beginPreservingViewport(.highlight)
            let selectedRange = textView.selectedRange
            let font = UIFont(
                name: parent.preferences.fontName,
                size: CGFloat(parent.preferences.fontSize)
            ) ?? UIFont.monospacedSystemFont(
                ofSize: CGFloat(parent.preferences.fontSize),
                weight: .regular
            )
            let palette = EditorPalette.resolve(
                appearance: appearance,
                traits: textView.traitCollection,
                customBackgroundHex: parent.preferences.customBackgroundHex,
                customForegroundHex: parent.preferences.customForegroundHex
            )
            let tier = LargeFilePolicy.tier(byteCount: 0, utf16Length: textView.textStorage.length)
            let keepsJSONSyntax = isLargeDocument
                && (parent.language == .json || parent.language == .jsonc)
                && LargeFilePolicy.allowsJSONHighlight(utf16Length: textView.textStorage.length)
            let shedsHighlight = LargeFilePolicy.disablesSyntaxHighlight(tier, language: parent.language)
                && !keepsJSONSyntax
            if (isLargeDocument && !keepsJSONSyntax) || shedsHighlight {
                // The text view already uses this font for newly assigned
                // text. Avoid a full-document attribute walk during opening;
                // it can otherwise block the main actor for seconds.
                textView.typingAttributes = [
                    .font: font,
                    .foregroundColor: palette.foreground
                ]
                bracketHighlightRanges.removeAll()
            } else {
                SyntaxHighlighter.apply(
                    to: textView,
                    language: parent.language,
                    font: font,
                    palette: palette
                )
                bracketHighlightRanges = SyntaxHighlighter.highlightMatchingBrackets(
                    in: textView,
                    selection: selectedRange,
                    palette: palette
                )
            }
            // Apply lightweight paragraph metrics after syntax highlighting so
            // user-configured spacing/alignment is retained across refreshes.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = CGFloat(parent.preferences.lineSpacing)
            switch parent.preferences.textAlignment {
            case .leading: paragraph.alignment = .left
            case .center: paragraph.alignment = .center
            case .trailing: paragraph.alignment = .right
            }
            textView.textStorage.addAttribute(
                .paragraphStyle,
                value: paragraph,
                range: NSRange(location: 0, length: textView.textStorage.length)
            )
            (textView as? LineNumberTextView)?.reapplyJSONFoldingAttributes()
            applySearchHighlights(to: textView)
            refreshBracketHighlight(textView)
            textView.selectedRange = selectedRange
            editor?.reapplyViewportAnchor()
            lastHighlightedContentRevision = parent.contentRevision
            lastLanguage = parent.language
            lastFontSize = parent.preferences.fontSize
            lastFontName = parent.preferences.fontName
            lastAppearance = appearance
            lastCustomBackground = parent.preferences.customBackgroundHex
            lastCustomForeground = parent.preferences.customForegroundHex
            DispatchQueue.main.async { [weak editor] in
                editor?.reapplyViewportAnchor()
                editor?.endPreservingViewport(.highlight)
            }
        }

        private func applySearchHighlights(to textView: UITextView) {
            let fullRange = NSRange(location: 0, length: textView.textStorage.length)
            let marker = UIColor.systemYellow.withAlphaComponent(0.34)
            let currentMarker = UIColor.systemOrange.withAlphaComponent(0.55)
            textView.textStorage.beginEditing()
            textView.textStorage.removeAttribute(.backgroundColor, range: fullRange)
            for range in searchHighlightRanges {
                let safe = NSIntersectionRange(range, fullRange)
                if safe.length > 0 {
                    textView.textStorage.addAttribute(.backgroundColor, value: marker, range: safe)
                }
            }
            let current = currentSearchHighlightRange
                ?? (searchHighlightRanges.contains(where: { NSEqualRanges($0, textView.selectedRange) })
                    ? textView.selectedRange : nil)
            if let current {
                let safe = NSIntersectionRange(current, fullRange)
                if safe.length > 0 {
                    textView.textStorage.addAttribute(.backgroundColor, value: currentMarker, range: safe)
                }
            }
            textView.textStorage.endEditing()
        }
    }
}

enum EditorNativeAction {
    case undo, redo, cut, copy, paste, selectAll, clearColumnSelection
    case selectNextOccurrence, clearMultiSelections
    case deleteJSONValue, foldCurrentJSON, foldAllJSON, unfoldAllJSON, formatJSON
}

extension Notification.Name {
    static let editorNativeAction = Notification.Name("NotepadPlus.editorNativeAction")
    static let workspaceWillActivateDocument = Notification.Name("NotepadPlus.workspaceWillActivateDocument")
    static let searchAllRequested = Notification.Name("NotepadPlus.searchAllRequested")
    static let markAllSearchRequested = Notification.Name("NotepadPlus.markAllSearchRequested")
    static let clearSearchMarksRequested = Notification.Name("NotepadPlus.clearSearchMarksRequested")
    static let editorSearchRevealSelection = Notification.Name("NotepadPlus.editorSearchRevealSelection")
    static let editorSearchHighlightsChanged = Notification.Name("NotepadPlus.editorSearchHighlightsChanged")
    static let editorSearchReplaceText = Notification.Name("NotepadPlus.editorSearchReplaceText")
    static let editorExternalContentReloaded = Notification.Name("NotepadPlus.editorExternalContentReloaded")
}

struct SearchReplacementRequest {
    let documentID: UUID
    let originalText: String
    let text: String
    let selection: NSRange
}

struct SearchSelectionRequest {
    let documentID: UUID
    let selection: NSRange
}

struct SearchHighlightRequest {
    let documentID: UUID
    let ranges: [NSRange]
    /// Distinct “current” match so next/previous navigation is visible in the
    /// buffer, not only in the find bar counter.
    var currentRange: NSRange? = nil
}

/// A one-shot search reveal can arrive before SwiftUI has attached the new
/// editor coordinator. Keep it by document until that coordinator is ready.
final class SearchRevealStore {
    static let shared = SearchRevealStore()
    private var pending: [UUID: NSRange] = [:]

    func set(_ selection: NSRange, for documentID: UUID) {
        pending[documentID] = selection
    }

    func consume(for documentID: UUID) -> NSRange? {
        defer { pending[documentID] = nil }
        return pending[documentID]
    }
}

/// Keeps the latest viewport independently of SwiftUI's update timing. A tab
/// can be replaced before the old representable's callback has propagated
/// through the workspace, so the UIKit-to-UIKit handoff needs a synchronous
/// per-document cache as well.
final class ScrollPositionStore {
    static let shared = ScrollPositionStore()

    private let store = DocumentScrollPositionStore()

    func set(
        _ offset: CGPoint,
        anchorLocation: Int = 0,
        anchorPixelDelta: CGFloat = 0,
        for documentID: UUID
    ) {
        store.set(
            EditorScrollPosition(
                x: offset.x,
                y: offset.y,
                anchorLocation: anchorLocation,
                anchorPixelDelta: Double(anchorPixelDelta)
            ),
            for: documentID
        )
    }

    func offset(for documentID: UUID) -> CGPoint? {
        guard let offset = store.offset(for: documentID) else { return nil }
        return CGPoint(x: offset.x, y: offset.y)
    }

    func position(for documentID: UUID) -> EditorScrollPosition? {
        store.offset(for: documentID)
    }

    func remove(for documentID: UUID) {
        store.remove(for: documentID)
    }
}

final class LineNumberTextView: UITextView {
    /// Handles the standard document-close command at the text view responder
    /// level. Mac Catalyst can route ⌘W to the window responder before the
    /// SwiftUI `CommandGroup` item is considered, so the menu binding alone is
    /// not reliable while the editor is first responder.
    var onCloseDocumentCommand: (() -> Void)?
    var onFindCommand: (() -> Void)?

    deinit {
        jsonFoldWorkItem?.cancel()
    }
    var onReplaceCommand: (() -> Void)?

    #if targetEnvironment(macCatalyst)
    override var keyCommands: [UIKeyCommand]? {
        var commands = super.keyCommands ?? []
        if closeCommandIsEnabled {
            commands.append(
                UIKeyCommand(
                    input: "w",
                    modifierFlags: [.command],
                    action: #selector(handleCloseDocumentCommand),
                    discoverabilityTitle: "关闭当前文档"
                )
            )
        }
        commands.append(
            UIKeyCommand(
                input: "f",
                modifierFlags: [.command],
                action: #selector(handleFindCommand),
                discoverabilityTitle: "查找与替换"
            )
        )
        commands.append(
            UIKeyCommand(
                input: "h",
                modifierFlags: [.command],
                action: #selector(handleReplaceCommand),
                discoverabilityTitle: "替换"
            )
        )
        return commands
    }

    @objc private func handleCloseDocumentCommand() {
        onCloseDocumentCommand?()
    }

    @objc private func handleFindCommand() {
        onFindCommand?()
    }

    @objc private func handleReplaceCommand() {
        onReplaceCommand?()
    }
    #endif

    var closeCommandIsEnabled = true

    var gutterWidth: CGFloat {
        rebuildLineNumberCacheIfNeeded()
        let pointSize = max((font?.pointSize ?? 15) - 2, 9)
        let digits = max(2, String(max(cachedLineStarts.count, 1)).count)
        let font = UIFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        let sample = String(repeating: "8", count: digits) as NSString
        return max(42, ceil(sample.size(withAttributes: [.font: font]).width) + 18)
    }
    var showLineNumbers = true {
        didSet {
            updateFoldGutterTapView()
            setNeedsDisplay()
        }
    }
    var showWhitespace = false {
        didSet { setNeedsDisplay() }
    }
    var editorPalette = EditorPalette.resolve(appearance: .system, traits: .current) {
        didSet { setNeedsDisplay() }
    }
    enum CodeFoldStyle: Equatable {
        case none
        case json
        case braces
    }

    var codeFoldStyle: CodeFoldStyle = .none {
        didSet {
            if codeFoldStyle == .none { foldedJSONLines.removeAll() }
            updateJSONFoldRegions()
            updateFoldGutterTapView()
        }
    }
    /// Backward-compatible alias used by draw/fold helpers.
    var jsonFoldingEnabled: Bool {
        get { codeFoldStyle != .none }
        set { codeFoldStyle = newValue ? (codeFoldStyle == .none ? .json : codeFoldStyle) : .none }
    }
    var onJSONFoldingChanged: (() -> Void)?
    private(set) var jsonFoldRegions: [Int: NSRange] = [:]
    private var foldedJSONLines: Set<Int> = []
    /// Additional carets/selections for Select Next Occurrence editing.
    private(set) var multiSelections: [NSRange] = []
    var hasMultiSelections: Bool { multiSelections.count > 1 }
    /// Logical line intervals hidden by currently collapsed JSON regions.
    /// Keeping these as merged intervals lets the gutter skip line numbers in
    /// O(log n) while drawing a large document, instead of checking every
    /// collapsed region for every visible glyph fragment.
    private var hiddenJSONLineIntervals: [(start: Int, end: Int)] = []
    private struct FoldedJSONSnapshot {
        let range: NSRange
        // Large JSON documents are intentionally kept in their baseline
        // typing style until they are edited. Copying an attributed snapshot
        // of a whole multi-megabyte root object would defeat the non-contiguous
        // layout optimization, so large ranges are restored from that baseline
        // instead of retaining another full document-sized buffer.
        let attributes: NSAttributedString?
    }
    private var foldedJSONSnapshots: [FoldedJSONSnapshot] = []
    private var jsonFoldGeneration = 0
    private var jsonFoldWorkItem: DispatchWorkItem?
    private var foldedSnapshotGeneration = -1
    private(set) var columnSelection: RectangularSelection?
    var columnTextDidChange: (() -> Void)?
    var contentOffsetDidChange: ((CGPoint) -> Void)?
    // Keep a local copy because some Mac Catalyst scroll paths do not invoke
    // every UIScrollView delegate callback before a view is replaced.
    private(set) var lastKnownContentOffset: CGPoint = .zero

    func rememberContentOffset(_ offset: CGPoint) {
        lastKnownContentOffset = offset
    }

    /// Why the viewport is being held. Each caller releases only its own
    /// reason, so a click cannot drop a tab-restore hold and highlighting
    /// cannot freeze later scrolling.
    enum ViewportHold: Hashable {
        case restore, highlight, click, externalReload
    }

    private var viewportHolds: Set<ViewportHold> = []
    private(set) var preservesViewport = false
    private var isApplyingPreservedOffset = false
    private var preservedContentOffset: CGPoint = .zero
    private var viewportAnchorLine = 0
    private var viewportAnchorPixelDelta: CGFloat = 0
    private var viewportAnchorLocation = 0
    private var lastHitPoint: CGPoint?
    private var clickStartPoint: CGPoint?
    /// Armed only for a stationary click. A drag or a cancelled touch (the
    /// scroll view took the gesture) clears it so flick-scrolling still moves.
    private var clickCorrectionArmed = false
    private var clickIsDrag = false
    /// After a tab restore, reject EOF selection jumps until the visible
    /// band has been interacted with or the guard expires.
    private var postRestoreGuardUntil: Date?
    private var allowScrollReveal = false
    private var cachedUniformLineHeight: CGFloat?
    private var cachedUniformLineHeightKey: String?
    /// The first visible line, in the same sense as Scintilla's `topLine`.
    var viewportAnchor: (location: Int, pixelDelta: CGFloat) {
        (viewportAnchorLocation, viewportAnchorPixelDelta)
    }

    func beginPreservingViewport(_ hold: ViewportHold) {
        if viewportHolds.isEmpty {
            captureViewportAnchor()
            preservedContentOffset = contentOffset
        }
        viewportHolds.insert(hold)
        preservesViewport = true
    }

    func endPreservingViewport(_ hold: ViewportHold) {
        viewportHolds.remove(hold)
        preservesViewport = !viewportHolds.isEmpty
        if !preservesViewport {
            captureViewportAnchor()
        }
    }

    /// Puts the saved line back on screen. Used after tab switches and after
    /// TextKit replaces an estimated content size.
    func restoreViewport(anchorLocation: Int, anchorPixelDelta: CGFloat, fallback: CGPoint) {
        if textContainer.widthTracksTextView {
            preservedContentOffset = fallback
            viewportAnchorLocation = anchorLocation
            viewportAnchorPixelDelta = anchorPixelDelta
            viewportHolds.insert(.restore)
            preservesViewport = true
            applyPreservedContentOffset(fallback)
            return
        }
        rebuildLineNumberCacheIfNeeded()
        let lineCount = max(cachedLineStarts.count, 1)
        let line: Int
        if anchorLocation > 0 || anchorPixelDelta != 0 || fallback.y != 0 {
            line = min(max(0, logicalLineNumber(atUTF16Offset: anchorLocation) - 1), lineCount - 1)
        } else {
            line = 0
        }
        viewportAnchorLine = line
        viewportAnchorLocation = cachedLineStarts.indices.contains(line) ? cachedLineStarts[line] : 0
        viewportAnchorPixelDelta = anchorPixelDelta
        let anchored = offsetForViewportAnchor()
        // A missing anchor (older sessions, brand new documents) still has a
        // pixel offset. Prefer the line when we have one so an estimated
        // content size cannot clamp the document to its end.
        let target = (anchorLocation > 0 || anchorPixelDelta != 0) ? anchored : fallback
        preservedContentOffset = CGPoint(x: fallback.x, y: target.y)
        viewportHolds.insert(.restore)
        preservesViewport = true
        applyPreservedContentOffset(preservedContentOffset)
    }

    func reapplyViewportAnchor() {
        guard preservesViewport || viewportAnchorLocation > 0 || viewportAnchorPixelDelta != 0 else { return }
        let target = offsetForViewportAnchor()
        preservedContentOffset = CGPoint(x: contentOffset.x, y: target.y)
        applyPreservedContentOffset(preservedContentOffset)
    }

    private func applyPreservedContentOffset(_ offset: CGPoint) {
        let inset = adjustedContentInset
        let minimumX = -inset.left
        let minimumY = -inset.top
        let maximumX = max(minimumX, contentSize.width - bounds.width + inset.right)
        let maximumY = max(minimumY, contentSize.height - bounds.height + inset.bottom)
        // UITextView clamps every assignment to the current content size.
        // While that size is still an estimate, pushing a line near the
        // middle clamps to the temporary end and the offset observer would
        // try the same assignment again.
        if textStorage.length > 0, offset.y > maximumY + 1 {
            return
        }
        let clamped = CGPoint(
            x: min(max(offset.x, minimumX), maximumX),
            y: min(max(offset.y, minimumY), maximumY)
        )
        guard abs(clamped.x - contentOffset.x) > 0.5 || abs(clamped.y - contentOffset.y) > 0.5 else { return }
        isApplyingPreservedOffset = true
        setContentOffset(clamped, animated: false)
        isApplyingPreservedOffset = false
    }

    private func captureViewportAnchor() {
        guard !textContainer.widthTracksTextView else {
            // Wrapped lines are not a fixed height. Keep the pixel offset;
            // the click guard below still stops a hit from jumping to EOF.
            viewportAnchorLocation = firstVisibleCharacterLocationByLayout()
            viewportAnchorPixelDelta = 0
            preservedContentOffset = contentOffset
            return
        }
        rebuildLineNumberCacheIfNeeded()
        let captured = ViewportAnchorMath.capture(
            contentOffsetY: contentOffset.y,
            insetTop: textContainerInset.top,
            lineHeight: uniformLineHeight(),
            lineCount: max(cachedLineStarts.count, 1)
        )
        viewportAnchorLine = captured.line
        viewportAnchorPixelDelta = CGFloat(captured.pixelDelta)
        viewportAnchorLocation = cachedLineStarts.indices.contains(captured.line) ? cachedLineStarts[captured.line] : 0
        preservedContentOffset = contentOffset
    }

    private func offsetForViewportAnchor() -> CGPoint {
        if textContainer.widthTracksTextView {
            return preservedContentOffset
        }
        let y = ViewportAnchorMath.contentOffsetY(
            line: viewportAnchorLine,
            pixelDelta: viewportAnchorPixelDelta,
            insetTop: textContainerInset.top,
            lineHeight: uniformLineHeight()
        )
        return CGPoint(x: preservedContentOffset.x, y: y)
    }

    private func uniformLineHeight() -> CGFloat {
        let spacing = paragraphLineSpacing()
        let key = "\(font?.fontName ?? "")-\(font?.pointSize ?? 0)-\(spacing)-\(textStorage.length > 0)"
        if key == cachedUniformLineHeightKey, let cachedUniformLineHeight {
            return cachedUniformLineHeight
        }
        var height = (font?.lineHeight ?? 18) + spacing
        if textStorage.length > 0, !textContainer.widthTracksTextView {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: 1))
            let glyph = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: 0, length: 1),
                actualCharacterRange: nil
            )
            if glyph.length > 0, glyph.location < layoutManager.numberOfGlyphs {
                let rect = layoutManager.lineFragmentRect(
                    forGlyphAt: glyph.location,
                    effectiveRange: nil,
                    withoutAdditionalLayout: true
                )
                if rect.height > 1 { height = rect.height }
            }
        }
        let resolved = max(1, height)
        cachedUniformLineHeight = resolved
        cachedUniformLineHeightKey = key
        return resolved
    }

    private func paragraphLineSpacing() -> CGFloat {
        guard textStorage.length > 0,
              let style = textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        else { return 0 }
        return style.lineSpacing
    }

    private func firstVisibleCharacterLocationByLayout() -> Int {
        guard textStorage.length > 0 else { return 0 }
        let y = max(0, contentOffset.y - textContainerInset.top)
        layoutManager.ensureLayout(
            forBoundingRect: CGRect(x: 0, y: y, width: max(bounds.width, 1), height: 4),
            in: textContainer
        )
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else { return 0 }
        let glyph = min(
            layoutManager.glyphIndex(for: CGPoint(x: textContainer.lineFragmentPadding, y: y), in: textContainer),
            glyphCount - 1
        )
        return min(layoutManager.characterIndexForGlyph(at: glyph), textStorage.length)
    }
    // UIKit can invoke selectAll directly for the standard Command-A action,
    // bypassing the SwiftUI command notification. Keep this flag on the view
    // so the delegate can skip rectangular-selection conversion on both paths.
    private(set) var isSelectingAllFast = false
    /// A full-document selection is represented virtually for large buffers.
    /// TextKit's native selectedRange setter eagerly lays out selection
    /// geometry across the entire document, which is prohibitively expensive
    /// for tens of megabytes. The coordinator still publishes this range to
    /// the document, while the text view keeps its existing lightweight caret.
    private(set) var virtualSelectionRange: NSRange?
    var selectionForBinding: NSRange { virtualSelectionRange ?? selectedRange }
    var onVirtualSelectionChanged: ((NSRange?) -> Void)?
    private var cachedLineStarts = [0]
    private var lineNumberCacheIsValid = false
    private var foldGutterTapView: FoldGutterTapView?

    var hasColumnSelection: Bool { columnSelection?.ranges.isEmpty == false }

    override var contentOffset: CGPoint {
        didSet {
            if preservesViewport, !isApplyingPreservedOffset {
                let lineHeight = uniformLineHeight()
                let jumped = abs(contentOffset.y - preservedContentOffset.y) > max(lineHeight * 3, 48)
                    || abs(contentOffset.x - preservedContentOffset.x) > 120
                if jumped {
                    applyPreservedContentOffset(offsetForViewportAnchor())
                    return
                }
            } else if !isApplyingPreservedOffset, oldValue != contentOffset, !(clickCorrectionArmed && !clickIsDrag) {
                // While a click is in flight, TextKit may assign an EOF offset.
                // Capturing that would make the later correction restore the end.
                captureViewportAnchor()
            }
            lastKnownContentOffset = contentOffset
            updateFoldGutterTapView()
            setNeedsDisplay()
            if oldValue != contentOffset, !preservesViewport {
                contentOffsetDidChange?(contentOffset)
            }
        }
    }

    override var contentSize: CGSize {
        didSet {
            guard !isApplyingPreservedOffset, oldValue != contentSize else { return }
            let shouldHold = preservesViewport || (clickCorrectionArmed && !clickIsDrag)
            guard shouldHold else { return }
            let target = offsetForViewportAnchor()
            let lineHeight = uniformLineHeight()
            // Ignore sub-line size changes. A jump of more than a few lines
            // is TextKit replacing an estimated height and clamping the offset
            // to the new end.
            guard abs(target.y - contentOffset.y) > lineHeight * 3 else { return }
            preservedContentOffset = CGPoint(x: preservedContentOffset.x, y: target.y)
            applyPreservedContentOffset(preservedContentOffset)
        }
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        // A click inside the visible text must not move the viewport. The
        // first TextKit hit after a non-contiguous layout often reports the
        // end of the buffer, and UITextView then scrolls that caret into view.
        if allowScrollReveal {
            super.scrollRangeToVisible(range)
            return
        }
        if preservesViewport { return }
        if isPostRestoreGuardActive, rangeIsFarFromViewport(range) { return }
        if clickCorrectionArmed, !clickIsDrag, rangeIsFarFromViewport(range) {
            return
        }
        super.scrollRangeToVisible(range)
    }

    /// Find next/previous must be able to scroll even while a restore hold is
    /// still draining.
    func revealRangeIgnoringViewportHold(_ range: NSRange) {
        allowScrollReveal = true
        defer { allowScrollReveal = false }
        layoutManager.ensureLayout(
            forCharacterRange: NSRange(location: max(0, range.location - 1), length: max(1, range.length + 2))
        )
        super.scrollRangeToVisible(range)
    }

    var isPostRestoreGuardActive: Bool {
        if let until = postRestoreGuardUntil, until > Date() { return true }
        return false
    }

    func armPostRestoreInteractionGuard(duration: TimeInterval = 1.2) {
        postRestoreGuardUntil = Date().addingTimeInterval(duration)
        captureViewportAnchor()
        // Force layout of the visible band so the first click has glyphs.
        let visible = CGRect(origin: contentOffset, size: bounds.size)
            .insetBy(dx: 0, dy: -textContainerInset.top)
        layoutManager.ensureLayout(forBoundingRect: visible, in: textContainer)
    }

    override var selectedTextRange: UITextRange? {
        get { super.selectedTextRange }
        set {
            if shouldRejectSelectionJump(newValue) {
                // Prefer the touch's own start point — closestPosition may have
                // overwritten lastHitPoint with a visible-local coordinate.
                if let point = clickStartPoint ?? lastHitPoint {
                    let index = characterIndex(atViewPoint: point)
                    if let position = position(from: beginningOfDocument, offset: index) {
                        super.selectedTextRange = textRange(from: position, to: position)
                        restoreViewportIfClickJumped()
                        return
                    }
                }
                // Keep the caret where it was rather than jumping to EOF.
                restoreViewportIfClickJumped()
                return
            }
            super.selectedTextRange = newValue
        }
    }

    private func shouldRejectSelectionJump(_ range: UITextRange?) -> Bool {
        guard let range else { return false }
        let location = offset(from: beginningOfDocument, to: range.start)
        let length = offset(from: range.start, to: range.end)
        let nsRange = NSRange(location: location, length: length)
        let guarding = (clickCorrectionArmed && !clickIsDrag) || isPostRestoreGuardActive
        guard guarding, rangeIsFarFromViewport(nsRange) else { return false }
        return true
    }

    private func rangeIsFarFromViewport(_ range: NSRange) -> Bool {
        rebuildLineNumberCacheIfNeeded()
        let targetLine = logicalLineNumber(atUTF16Offset: range.location)
        // Prefer the live scroll position. After a tab restore the stored
        // viewportAnchorLocation can briefly lag at 0/EOF while the user is
        // already looking at the middle of the file; comparing against that
        // stale anchor rejects the real click and "corrects" to the wrong line.
        let visibleLocation: Int
        if !textContainer.widthTracksTextView {
            let lineHeight = uniformLineHeight()
            let line = max(0, Int(floor(max(0, contentOffset.y - textContainerInset.top) / lineHeight)))
            visibleLocation = cachedLineStarts.indices.contains(line) ? cachedLineStarts[line] : 0
        } else {
            visibleLocation = firstVisibleCharacterLocationByLayout()
        }
        let visibleLine = logicalLineNumber(atUTF16Offset: visibleLocation)
        let linesOnScreen = max(1, Int(bounds.height / uniformLineHeight()))
        return abs(targetLine - visibleLine) > linesOnScreen + 2
    }

    override func closestPosition(to point: CGPoint) -> UITextPosition? {
        let content = contentPoint(for: point)
        lastHitPoint = content
        let index = characterIndex(atViewPoint: content)
        return position(from: beginningOfDocument, offset: index) ?? super.closestPosition(to: point)
    }

    override func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? {
        closestPosition(to: point) ?? super.closestPosition(to: point, within: range)
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        // Select All keeps a zero-length native caret so TextKit does not
        // build selection rects. Hide that caret while the virtual highlight
        // is showing, matching Scintilla's stream selection.
        if virtualSelectionRange != nil { return .zero }
        return super.caretRect(for: position)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let raw = touches.first?.location(in: self)
        let point = raw.map { contentPoint(for: $0) }
        clickStartPoint = point
        lastHitPoint = point
        clickIsDrag = false
        captureViewportAnchor()
        clickCorrectionArmed = true
        // Place the caret on the line the user is looking at *before* UIKit's
        // non-contiguous hit tester runs. After a tab switch that tester often
        // reports index 0 or EOF, which is what scrolled the viewport away.
        if let point, virtualSelectionRange == nil {
            let index = characterIndex(atViewPoint: point)
            if let position = position(from: beginningOfDocument, offset: index) {
                super.selectedTextRange = textRange(from: position, to: position)
            }
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let point = touches.first?.location(in: self),
           let start = clickStartPoint,
           abs(point.y - start.y) > uniformLineHeight() * 2 || abs(point.x - start.x) > 12 {
            // A drag extends the selection and is allowed to scroll.
            clickIsDrag = true
            clickCorrectionArmed = false
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let raw = touches.first?.location(in: self) ?? clickStartPoint
        let point = raw.map { contentPoint(for: $0) } ?? clickStartPoint
        if let point, jsonFoldingEnabled, point.x <= textContainerInset.left + contentOffset.x {
            clickCorrectionArmed = false
            toggleJSONFoldFromGutter(at: point)
            return
        }
        super.touchesEnded(touches, with: event)
        guard clickCorrectionArmed, !clickIsDrag else { return }
        correctSelectionAfterClick(at: point)
        restoreViewportIfClickJumped()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.clickCorrectionArmed, !self.clickIsDrag else { return }
            self.correctSelectionAfterClick(at: self.clickStartPoint ?? point)
            self.restoreViewportIfClickJumped()
            self.clickCorrectionArmed = false
            self.postRestoreGuardUntil = nil
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // UIScrollView cancels the touch once a pan/wheel scroll wins.
        clickCorrectionArmed = false
        clickIsDrag = true
        super.touchesCancelled(touches, with: event)
    }

    private func restoreViewportIfClickJumped() {
        let target = offsetForViewportAnchor()
        let lineHeight = uniformLineHeight()
        guard abs(contentOffset.y - target.y) > lineHeight * 3
                || abs(contentOffset.x - target.x) > 120 else { return }
        preservedContentOffset = target
        applyPreservedContentOffset(target)
    }

    /// Catalyst / UIKit sometimes hand us a visible-local point (origin at the
    /// top-left of what is on screen, y in `0...bounds.height`) and sometimes a
    /// content point (`bounds.origin` / `contentOffset` already applied). Map
    /// both to content space before line math so a mid-file click cannot be
    /// resolved as line 1 after a tab restore.
    private func contentPoint(for point: CGPoint) -> CGPoint {
        let offset = contentOffset
        var x = point.x
        var y = point.y
        // Visible-local points sit in 0...bounds.size while content points for
        // the same pixel already include contentOffset (== bounds.origin).
        if offset.y > 1, y < offset.y - 1, y >= -1, y <= bounds.height + 48 {
            y += offset.y
        }
        if offset.x > 1, x < offset.x - 1, x >= -1, x <= bounds.width + 48 {
            x += offset.x
        }
        return CGPoint(x: x, y: y)
    }

    /// Resolves a click from the line the user is looking at. TextKit's
    /// non-contiguous hit testing can return the last glyph until that band
    /// has been laid out; the line index does not depend on that cache.
    func characterIndex(atViewPoint point: CGPoint) -> Int {
        let length = textStorage.length
        guard length > 0 else { return 0 }
        let point = contentPoint(for: point)
        rebuildLineNumberCacheIfNeeded()
        if textContainer.widthTracksTextView {
            return wrappedCharacterIndex(at: point, length: length)
        }
        let lineHeight = uniformLineHeight()
        let textY = point.y - textContainerInset.top
        var lineIndex = Int(floor(textY / lineHeight))
        if textY < 0 { lineIndex = 0 }
        lineIndex = min(max(0, lineIndex), max(0, cachedLineStarts.count - 1))
        let lineStart = cachedLineStarts[lineIndex]
        let next = lineIndex + 1 < cachedLineStarts.count ? cachedLineStarts[lineIndex + 1] : length
        let lineSpan = max(0, next - lineStart)
        let newline = lineSpan > 0 && isNewline(at: lineStart + lineSpan - 1) ? 1 : 0
        let contentLength = max(0, lineSpan - newline)
        guard contentLength > 0 else { return lineStart }
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: lineStart, length: max(1, lineSpan)))
        let containerPoint = CGPoint(
            x: max(0, point.x - textContainerInset.left),
            y: CGFloat(lineIndex) * lineHeight + lineHeight * 0.5
        )
        var fraction: CGFloat = 0
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else { return lineStart }
        let glyph = min(
            layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction),
            glyphCount - 1
        )
        var index = layoutManager.characterIndexForGlyph(at: glyph)
        if index < lineStart || index > lineStart + contentLength {
            // glyphIndex fell through to EOF. Stay on this line and pick the
            // glyph whose horizontal bounds contain the click, including
            // full-width characters.
            index = columnOnLine(
                lineStart: lineStart,
                lineSpan: max(lineSpan, 1),
                contentLength: contentLength,
                containerX: containerPoint.x
            )
            return index
        }
        if fraction >= 0.5, index < lineStart + contentLength { index += 1 }
        return min(index, lineStart + contentLength)
    }

    private func columnOnLine(lineStart: Int, lineSpan: Int, contentLength: Int, containerX: CGFloat) -> Int {
        let glyphs = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: lineStart, length: lineSpan),
            actualCharacterRange: nil
        )
        guard glyphs.length > 0 else { return lineStart }
        var low = glyphs.location
        var high = glyphs.location + glyphs.length
        while low < high {
            let middle = low + (high - low) / 2
            let rect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: middle, length: 1),
                in: textContainer
            )
            if containerX < rect.midX {
                high = middle
            } else {
                low = middle + 1
            }
        }
        let glyph = min(max(low, glyphs.location), glyphs.location + glyphs.length - 1)
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        let rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyph, length: 1),
            in: textContainer
        )
        var index = character
        if containerX >= rect.midX { index += 1 }
        return min(max(index, lineStart), lineStart + contentLength)
    }

    private func wrappedCharacterIndex(at point: CGPoint, length: Int) -> Int {
        let containerPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        let band = CGRect(
            x: 0,
            y: max(0, containerPoint.y - uniformLineHeight()),
            width: max(bounds.width, 1),
            height: uniformLineHeight() * 3
        )
        layoutManager.ensureLayout(forBoundingRect: band, in: textContainer)
        if let emptyLineStart = emptyWrappedLineStart(at: containerPoint, length: length) {
            return emptyLineStart
        }
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else { return 0 }
        var fraction: CGFloat = 0
        let glyph = min(
            layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction),
            glyphCount - 1
        )
        var index = layoutManager.characterIndexForGlyph(at: glyph)
        // Stay on an empty / newline-only line: advancing by fraction would
        // jump the caret to the next content line, which is what made blank
        // lines in chat logs untappable.
        rebuildLineNumberCacheIfNeeded()
        let line = logicalLineNumber(atUTF16Offset: index)
        let lineStart = cachedLineStarts[max(0, line - 1)]
        let next = line < cachedLineStarts.count ? cachedLineStarts[line] : length
        let lineSpan = max(0, next - lineStart)
        let newline = lineSpan > 0 && isNewline(at: lineStart + lineSpan - 1) ? 1 : 0
        let contentLength = max(0, lineSpan - newline)
        if contentLength == 0 {
            return lineStart
        }
        if fraction >= 0.5, index < lineStart + contentLength { index += 1 }
        return min(max(lineStart, index), lineStart + contentLength)
    }

    /// When the click lands on a wrapped empty line fragment, return that
    /// line's start. TextKit's glyphIndex often drifts to a neighbour glyph.
    private func emptyWrappedLineStart(at containerPoint: CGPoint, length: Int) -> Int? {
        guard length > 0, layoutManager.numberOfGlyphs > 0 else { return nil }
        var result: Int?
        let probe = CGRect(
            x: 0,
            y: max(0, containerPoint.y - 1),
            width: max(textContainer.size.width, bounds.width, 1),
            height: max(2, uniformLineHeight())
        )
        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(forBoundingRect: probe, in: textContainer)) {
            rect, usedRect, _, glyphRange, stop in
            guard containerPoint.y >= rect.minY - 0.5, containerPoint.y < rect.maxY + 0.5 else { return }
            let characters = self.layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            guard characters.length > 0 else { return }
            let onlyNewline = characters.length == 1 && self.isNewline(at: characters.location)
            let visuallyEmpty = usedRect.width <= self.textContainer.lineFragmentPadding + 1
            if onlyNewline || visuallyEmpty {
                result = characters.location
                stop.pointee = true
            }
        }
        return result
    }

    private func isNewline(at index: Int) -> Bool {
        guard index >= 0, index < textStorage.length else { return false }
        let slice = textStorage.attributedSubstring(from: NSRange(location: index, length: 1)).string
        return slice == "\n" || slice == "\r"
    }

    private func correctSelectionAfterClick(at point: CGPoint?) {
        guard let point, virtualSelectionRange == nil else { return }
        let index = characterIndex(atViewPoint: point)
        let corrected = NSRange(location: index, length: 0)
        // A stationary click always wins over TextKit's EOF/line-0 guess.
        // Previously we only corrected when the selection looked "far" from a
        // (sometimes stale) viewport anchor, which let the first click after a
        // tab switch stick at the document head or tail.
        if selectedRange != corrected {
            if let position = position(from: beginningOfDocument, offset: index) {
                super.selectedTextRange = textRange(from: position, to: position)
            } else {
                selectedRange = corrected
            }
        }
        // Empty-line clicks can leave the caret glued to the previous visual
        // line (upstream affinity on the newline). If the caret is clearly
        // above the click, re-apply after ensuring that line's layout.
        if let position = position(from: beginningOfDocument, offset: index) {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: index, length: max(1, min(1, textStorage.length - index))))
            let caret = caretRect(for: position)
            if caret.minY + caret.height * 0.5 < point.y - uniformLineHeight() * 0.4 {
                super.selectedTextRange = textRange(from: position, to: position)
            }
        }
        applyPreservedContentOffset(offsetForViewportAnchor())
        postRestoreGuardUntil = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateFoldGutterTapView()
        setNeedsDisplay()
    }

    private func updateFoldGutterTapView() {
        guard jsonFoldingEnabled, showLineNumbers else {
            foldGutterTapView?.isHidden = true
            return
        }
        if foldGutterTapView == nil {
            let tapView = FoldGutterTapView()
            tapView.onTap = { [weak self, weak tapView] point in
                guard let self, tapView != nil else { return }
                // The recognizer reports a point in the overlay's local
                // coordinate system. Convert it to the text view's
                // coordinate system before resolving the document position;
                // after scrolling, using the raw overlay point resolves the
                // click against the wrong (usually top/root) line.
                let textPoint = tapView?.convert(point, to: self) ?? point
                self.toggleJSONFoldFromGutter(at: textPoint)
            }
            addSubview(tapView)
            foldGutterTapView = tapView
        }
        // UIScrollView's bounds origin follows contentOffset (and may include
        // adjusted insets). Pin to the actual bounds origin rather than
        // duplicating contentOffset; this keeps the hit target aligned while
        // scrolling and during the initial inset/layout pass.
        // Keep the hit target at least as wide as the actual text inset.  The
        // fold mark is drawn at the left edge of the line-number gutter, but
        // the inset can be wider than `gutterWidth` while the font/line-count
        // configuration is being applied.  A stale narrow overlay makes the
        // visible minus sign look clickable while the touch is delivered to
        // the text view underneath.
        foldGutterTapView?.frame = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(gutterWidth, textContainerInset.left),
            height: bounds.height
        )
        foldGutterTapView?.isHidden = false
        if let foldGutterTapView { bringSubviewToFront(foldGutterTapView) }
    }

    override func draw(_ rect: CGRect) {
        rebuildLineNumberCacheIfNeeded()
        let gutterRect = CGRect(
            x: contentOffset.x,
            y: contentOffset.y,
            width: showLineNumbers ? gutterWidth : 0,
            height: bounds.height
        )
        editorPalette.gutterBackground.setFill()
        UIRectFill(gutterRect)
        super.draw(rect)

        drawVirtualSelection()
        drawColumnSelection()
        drawMultiSelections()
        if showWhitespace { drawWhitespaceMarkers() }

        guard showLineNumbers, let font = font else { return }
        let visibleRect = CGRect(origin: contentOffset, size: bounds.size)
            .insetBy(dx: 0, dy: -textContainerInset.top)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: max(font.pointSize - 2, 9), weight: .regular),
            .foregroundColor: editorPalette.gutterForeground
        ]

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [weak self] rect, _, _, glyphRange, _ in
            guard let self else { return }
            let characterIndex = min(
                self.layoutManager.characterIndexForGlyph(at: glyphRange.location),
                (self.text as NSString).length
            )
            let insertion = self.cachedLineStarts.partitioningIndex { $0 >= characterIndex }
            let lineIndex: Int
            if insertion < self.cachedLineStarts.count, self.cachedLineStarts[insertion] == characterIndex {
                lineIndex = insertion
            } else {
                lineIndex = max(0, insertion - 1)
                // A wrapped continuation is not a new logical line and should not repeat the number.
                guard self.cachedLineStarts[lineIndex] == characterIndex else { return }
            }
            let lineNumber = lineIndex + 1
            // A collapsed region hides the child lines through its matching
            // closing delimiter. Keep those rows visually empty in the
            // gutter, just like mature code editors do; the opening row keeps
            // its fold control.
            if self.isLineHiddenByJSONFold(lineNumber) { return }
            let value = "\(lineNumber)" as NSString
            let size = value.size(withAttributes: attributes)
            let point = CGPoint(
                x: self.contentOffset.x + self.gutterWidth - size.width - 7,
                y: rect.minY + self.textContainerInset.top + (rect.height - size.height) / 2
            )
            value.draw(at: point, withAttributes: attributes)
            if self.jsonFoldingEnabled, self.jsonFoldRegions[lineNumber] != nil {
                // Use the familiar +/- affordance used by Notepad++ and
                // other source editors instead of decorative triangles.
                let symbol = self.foldedJSONLines.contains(lineNumber) ? "+" : "−"
                let symbolAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: max(font.pointSize - 2, 10), weight: .semibold),
                    .foregroundColor: self.editorPalette.gutterForeground
                ]
                (symbol as NSString).draw(
                    at: CGPoint(x: self.contentOffset.x + 3, y: point.y),
                    withAttributes: symbolAttributes
                )
            }
        }
    }

    /// Draw whitespace as a paint-only overlay.  The underlying string is
    /// untouched, so toggling this option is instant and remains safe for
    /// multi-megabyte documents.  Only glyphs in the visible viewport are
    /// inspected.
    private func drawWhitespaceMarkers() {
        guard let font else { return }
        let visibleRect = CGRect(origin: contentOffset, size: bounds.size)
            .insetBy(dx: 0, dy: -textContainerInset.top)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let source = textStorage.string as NSString
        guard characterRange.length > 0 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: max(font.pointSize - 5, 7), weight: .medium),
            .foregroundColor: editorPalette.gutterForeground.withAlphaComponent(0.65)
        ]
        var drawn = 0
        let end = min(NSMaxRange(characterRange), source.length)
        for index in characterRange.location..<end {
            guard drawn < 5_000 else { break }
            let value = source.character(at: index)
            guard value == 0x20 || value == 0x09 else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let marker = value == 0x09 ? "→" : "·"
            let size = (marker as NSString).size(withAttributes: attributes)
            let point = CGPoint(
                x: glyphRect.midX + textContainerInset.left - size.width / 2,
                y: glyphRect.midY + textContainerInset.top - size.height / 2
            )
            (marker as NSString).draw(at: point, withAttributes: attributes)
            drawn += 1
        }
    }

    func updateJSONFoldRegions() {
        guard codeFoldStyle != .none else {
            jsonFoldWorkItem?.cancel()
            jsonFoldWorkItem = nil
            jsonFoldRegions = [:]
            foldedJSONLines.removeAll()
            reapplyJSONFoldingAttributes()
            setNeedsDisplay()
            return
        }
        jsonFoldGeneration &+= 1
        let generation = jsonFoldGeneration
        let source = text ?? ""
        let style = codeFoldStyle
        jsonFoldWorkItem?.cancel()
        jsonFoldRegions = [:]
        foldedJSONLines.removeAll()
        reapplyJSONFoldingAttributes()

        // Folding follows the same strategy used by mature code editors:
        // build a lightweight delimiter index off the UI thread, then publish
        // it atomically. Opening, selecting and typing in a large document do
        // not wait for a full parse.
        let workItem = DispatchWorkItem { [weak self] in
            let regions: [Int: NSRange]
            switch style {
            case .json: regions = JSONFolding.regions(in: source)
            case .braces: regions = BraceFolding.regions(in: source)
            case .none: regions = [:]
            }
            guard !Thread.current.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.codeFoldStyle == style,
                      self.jsonFoldGeneration == generation,
                      self.text == source else { return }
                self.jsonFoldRegions = regions
                self.foldedJSONLines = self.foldedJSONLines.filter { regions[$0] != nil }
                self.reapplyJSONFoldingAttributes()
                self.setNeedsDisplay()
            }
        }
        jsonFoldWorkItem = workItem
        if textStorage.length >= EditorPerformance.deferredProcessingUTF16Length {
            DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
        } else {
            DispatchQueue.main.async(execute: workItem)
        }
    }

    func reapplyJSONFoldingAttributes() {
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        restoreJSONFoldSnapshots(in: fullRange)
        rebuildHiddenJSONLineIntervals()
        guard fullRange.length > 0 else { return }

        // Nested regions are collapsed into their outermost ranges. This is
        // important for “折叠全部” on a large JSON file: applying thousands of
        // overlapping attributes would otherwise turn an O(n) action into an
        // O(n²) relayout.
        let regions = foldedJSONLines.compactMap { line -> (Int, NSRange)? in
            guard let range = jsonFoldRegions[line] else { return nil }
            return (line, NSIntersectionRange(range, fullRange))
        }
        .filter { $0.1.length > 0 }
        .sorted { lhs, rhs in
            if lhs.1.location != rhs.1.location { return lhs.1.location < rhs.1.location }
            return lhs.1.length > rhs.1.length
        }
        var effective: [(Int, NSRange)] = []
        for region in regions {
            if let outer = effective.last, NSMaxRange(region.1) <= NSMaxRange(outer.1) { continue }
            effective.append(region)
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 0
        paragraph.maximumLineHeight = 0
        textStorage.beginEditing()
        for (_, range) in effective {
            foldedJSONSnapshots.append(FoldedJSONSnapshot(
                range: range,
                attributes: range.length <= 200_000
                    ? textStorage.attributedSubstring(from: range)
                    : nil
            ))
            textStorage.addAttributes([
                .font: UIFont.systemFont(ofSize: 0.1),
                .foregroundColor: UIColor.clear,
                .paragraphStyle: paragraph
            ], range: range)
        }
        textStorage.endEditing()
        foldedSnapshotGeneration = jsonFoldGeneration
        invalidateLineNumberCache()
        setNeedsLayout()
    }

    /// Rebuilds merged logical-line intervals hidden by collapsed regions.
    /// Fold ranges are character ranges between the opening and closing
    /// delimiters, so converting only their endpoints keeps this linear in
    /// the number of collapsed regions and avoids rescanning the text.
    private func rebuildHiddenJSONLineIntervals() {
        guard jsonFoldingEnabled, !foldedJSONLines.isEmpty, !jsonFoldRegions.isEmpty else {
            hiddenJSONLineIntervals.removeAll(keepingCapacity: true)
            return
        }
        rebuildLineNumberCacheIfNeeded()
        var intervals: [(start: Int, end: Int)] = []
        intervals.reserveCapacity(foldedJSONLines.count)
        for line in foldedJSONLines {
            guard let range = jsonFoldRegions[line], range.length > 0 else { continue }
            let startLine = logicalLineNumber(atUTF16Offset: range.location)
            let endOffset = max(range.location, NSMaxRange(range) - 1)
            let endLine = logicalLineNumber(atUTF16Offset: endOffset)
            if endLine >= startLine { intervals.append((startLine, endLine)) }
        }
        intervals.sort { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
        var merged: [(start: Int, end: Int)] = []
        for interval in intervals {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end + 1 {
                merged[merged.count - 1] = (last.start, max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }
        hiddenJSONLineIntervals = merged
    }

    private func logicalLineNumber(atUTF16Offset offset: Int) -> Int {
        let clamped = min(max(offset, 0), (text as NSString).length)
        let insertion = cachedLineStarts.partitioningIndex { $0 > clamped }
        return max(1, insertion)
    }

    private func isLineHiddenByJSONFold(_ line: Int) -> Bool {
        guard !hiddenJSONLineIntervals.isEmpty else { return false }
        var low = 0
        var high = hiddenJSONLineIntervals.count
        while low < high {
            let middle = low + (high - low) / 2
            if hiddenJSONLineIntervals[middle].start <= line {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let candidate = low - 1
        return candidate >= 0 && line <= hiddenJSONLineIntervals[candidate].end
    }

    private func restoreJSONFoldSnapshots(in fullRange: NSRange) {
        guard !foldedJSONSnapshots.isEmpty else { return }
        textStorage.beginEditing()
        if foldedSnapshotGeneration == jsonFoldGeneration {
            for snapshot in foldedJSONSnapshots {
                let safe = NSIntersectionRange(snapshot.range, fullRange)
                guard safe.length > 0 else { continue }
                if let attributes = snapshot.attributes {
                    attributes.enumerateAttributes(
                        in: NSRange(location: 0, length: min(attributes.length, safe.length)),
                        options: []
                    ) { attributes, range, _ in
                        let target = NSRange(location: safe.location + range.location, length: min(range.length, safe.length - range.location))
                        if target.length > 0 { self.textStorage.addAttributes(attributes, range: target) }
                    }
                } else {
                    let baseline: [NSAttributedString.Key: Any] = [
                        .font: font ?? UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                        .foregroundColor: editorPalette.foreground,
                        .paragraphStyle: NSParagraphStyle.default
                    ]
                    textStorage.addAttributes(baseline, range: safe)
                }
            }
        } else {
            // Content changed while a region was folded. The old attributed
            // substring is no longer safe to restore, so return its old range
            // to the editor's baseline style and let the highlighter refresh.
            let baseline: [NSAttributedString.Key: Any] = [
                .font: font ?? UIFont.monospacedSystemFont(ofSize: 15, weight: .regular),
                .foregroundColor: editorPalette.foreground,
                .paragraphStyle: NSParagraphStyle.default
            ]
            for snapshot in foldedJSONSnapshots {
                let safe = NSIntersectionRange(snapshot.range, fullRange)
                if safe.length > 0 { textStorage.addAttributes(baseline, range: safe) }
            }
        }
        textStorage.endEditing()
        foldedJSONSnapshots.removeAll()
        foldedSnapshotGeneration = -1
    }

    func toggleJSONFoldFromCoordinator(at line: Int) {
        guard jsonFoldingEnabled, jsonFoldRegions[line] != nil else { return }
        if foldedJSONLines.contains(line) { foldedJSONLines.remove(line) }
        else { foldedJSONLines.insert(line) }
        reapplyJSONFoldingAttributes()
        setNeedsDisplay()
        onJSONFoldingChanged?()
    }

    /// Finds the smallest foldable JSON container containing the caret or
    /// selection. Using character ranges instead of only the current line
    /// handles nested containers and multiple delimiters on one line, which
    /// is how mature editors implement “fold current block”.
    func jsonFoldLine(containing selection: NSRange) -> Int? {
        guard jsonFoldingEnabled, !jsonFoldRegions.isEmpty else { return nil }
        let sourceLength = (text as NSString).length
        let location = min(max(selection.location, 0), sourceLength)
        let selectionEnd = min(max(NSMaxRange(selection), location), sourceLength)
        let currentLine = TextStatistics.lineAndColumn(in: text, utf16Location: location).line

        // A fold range starts on the line *after* its opening delimiter.  A
        // right-click on the opening line therefore cannot be tested using
        // `range.location <= caret`; use that line's actual start as the
        // header hit area instead.  The old implementation returned any
        // region whose key matched the current line, even when the caret was
        // on a different token; when the menu supplied a stale/whole-document
        // selection this selected the root object and folded the entire tail.
        rebuildLineNumberCacheIfNeeded()
        let currentLineStart = (currentLine > 0 && currentLine - 1 < cachedLineStarts.count)
            ? cachedLineStarts[currentLine - 1]
            : 0
        let candidates = jsonFoldRegions.compactMap { line, range -> (line: Int, range: NSRange)? in
            let end = NSMaxRange(range)
            // The gutter/menu hit can land anywhere on the opening line (not
            // only on the delimiter itself).  Treat the whole header row as
            // that container's hit target, as Scintilla does.
            let onHeader = line == currentLine && location >= currentLineStart
            let inBody = range.location <= location && location <= end
            guard onHeader || inBody else { return nil }

            // For an actual text selection, prefer a container enclosing the
            // whole selection.  This prevents a selection beginning in an
            // outer object from accidentally choosing that outer object when
            // the pointer/menu is over a nested bracket.
            if selection.length > 0,
               !onHeader,
               !(range.location <= location && selectionEnd <= end) {
                return nil
            }
            return (line, range)
        }
        return candidates.min {
            if $0.range.length != $1.range.length { return $0.range.length < $1.range.length }
            return $0.range.location > $1.range.location
        }?.line
    }

    func isJSONFoldCollapsed(at line: Int) -> Bool {
        foldedJSONLines.contains(line)
    }

    func toggleJSONFold(at line: Int) {
        toggleJSONFoldFromCoordinator(at: line)
    }

    func setAllJSONFolds(collapsed: Bool) {
        guard jsonFoldingEnabled else { return }
        foldedJSONLines = collapsed ? Set(jsonFoldRegions.keys) : []
        reapplyJSONFoldingAttributes()
        setNeedsDisplay()
        onJSONFoldingChanged?()
    }

    func deleteJSONValue(at selection: NSRange) -> NSRange? {
        guard jsonFoldingEnabled else { return nil }
        let source = text ?? ""
        guard let range = JSONValueEditing.deletionRange(in: source, selection: selection), range.length > 0 else {
            return nil
        }
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return nil }
        replace(textRange, withText: "")
        selectedRange = NSRange(location: min(range.location, (text as NSString).length), length: 0)
        return range
    }

    private func toggleJSONFoldFromGutter(at point: CGPoint) {
        guard jsonFoldingEnabled else { return }
        guard textStorage.length > 0 else { return }
        // Do not use closestPosition(to:) here.  On Catalyst it is allowed to
        // return the nearest *editable* position (and can return nil while a
        // large, non-contiguous TextKit layout is catching up), so a click on
        // a visible fold mark was silently ignored.  Resolve the hit from the
        // line fragment/glyph geometry instead.  `point` is in this
        // scroll-view's bounds coordinate system, therefore its y value already
        // includes contentOffset; subtract only the text-container inset.
        let documentPoint = CGPoint(
            x: textContainerInset.left + 1,
            y: point.y - textContainerInset.top
        )
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else { return }
        var glyph = layoutManager.glyphIndex(for: documentPoint, in: textContainer)
        glyph = min(max(glyph, 0), glyphCount - 1)
        let character = min(
            layoutManager.characterIndexForGlyph(at: glyph),
            textStorage.length
        )
        rebuildLineNumberCacheIfNeeded()
        let line = logicalLineNumber(atUTF16Offset: character)

        // Normally the marker is on the opening line itself.  If a pointer is
        // a few pixels below the marker (common when the line is partially
        // clipped at the top of the viewport), accept the nearest enclosing
        // fold as well.  This keeps the gutter forgiving without ever falling
        // back to the root object or folding the remainder of the file.
        if jsonFoldRegions[line] != nil {
            toggleJSONFoldFromCoordinator(at: line)
            return
        }
        let containing = jsonFoldRegions.compactMap { foldLine, range -> Int? in
            let rangeEnd = NSMaxRange(range)
            let startLine = logicalLineNumber(atUTF16Offset: range.location)
            let endLine = logicalLineNumber(atUTF16Offset: max(range.location, rangeEnd - 1))
            guard foldLine < line, line >= startLine, line <= endLine else { return nil }
            return foldLine
        }.max()
        if let containing {
            toggleJSONFoldFromCoordinator(at: containing)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Keep the dedicated gutter layer above TextKit's editing gestures.
        // Catalyst can otherwise route a click on the minus sign to the
        // UITextView and the fold action appears to do nothing.
        if let foldGutterTapView, !foldGutterTapView.isHidden {
            // `hitTest` receives a point in the view's bounds coordinate
            // space.  The overlay is pinned to `bounds.minX/minY`, so test
            // that viewport rect explicitly before converting to the overlay
            // (this remains correct even when contentOffset is non-zero).
            let gutterRect = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: foldGutterTapView.bounds.width,
                height: bounds.height
            )
            if gutterRect.contains(point) {
                let localPoint = foldGutterTapView.convert(point, from: self)
                return foldGutterTapView.hitTest(localPoint, with: event) ?? foldGutterTapView
            }
        }
        return super.hitTest(point, with: event)
    }

    func setColumnSelection(_ selection: RectangularSelection) {
        columnSelection = selection
        setNeedsDisplay()
    }

    func clearColumnSelection() {
        guard columnSelection != nil else { return }
        columnSelection = nil
        setNeedsDisplay()
    }

    func clearMultiSelections() {
        guard !multiSelections.isEmpty else { return }
        multiSelections = []
        setNeedsDisplay()
    }

    /// Adds the next identical occurrence to the multi-caret set (VS Code /
    /// Sublime “Select Next Occurrence”). The primary `selectedRange` tracks
    /// the newest match so Go To / status bar stay coherent.
    @discardableResult
    func selectNextOccurrence() -> Bool {
        clearColumnSelection()
        clearVirtualSelection(notify: false)
        let source = text as NSString
        guard source.length > 0 else { return false }

        var seed = selectedRange
        if seed.length == 0 {
            seed = wordRange(at: seed.location) ?? seed
            guard seed.length > 0 else { return false }
            selectedRange = seed
        }
        let query = source.substring(with: seed)
        guard !query.isEmpty else { return false }

        var selections = multiSelections
        if selections.isEmpty {
            selections = [seed]
        } else if !selections.contains(where: { NSEqualRanges($0, seed) }) {
            selections.append(seed)
        }

        let searchStart = selections.map { NSMaxRange($0) }.max() ?? NSMaxRange(seed)
        let haystack = source as String
        let options: String.CompareOptions = []
        let nextRange: NSRange?
        if searchStart < source.length,
           let searchLimits = Range(NSRange(location: searchStart, length: source.length - searchStart), in: haystack),
           let found = haystack.range(of: query, options: options, range: searchLimits) {
            nextRange = NSRange(found, in: haystack)
        } else if let wrapLimits = Range(NSRange(location: 0, length: max(0, searchStart)), in: haystack),
                  let found = haystack.range(of: query, options: options, range: wrapLimits) {
            // Wrap around once, skipping ranges already selected.
            let candidate = NSRange(found, in: haystack)
            nextRange = selections.contains(where: { NSEqualRanges($0, candidate) }) ? nil : candidate
        } else {
            nextRange = nil
        }

        guard let next = nextRange else {
            multiSelections = selections
            setNeedsDisplay()
            return false
        }
        if !selections.contains(where: { NSEqualRanges($0, next) }) {
            selections.append(next)
        }
        selections.sort { $0.location < $1.location }
        multiSelections = selections
        selectedRange = next
        scrollRangeToVisible(next)
        setNeedsDisplay()
        return true
    }

    private func wordRange(at location: Int) -> NSRange? {
        let source = text as NSString
        guard source.length > 0 else { return nil }
        let probe = min(max(0, location), max(0, source.length - 1))
        let identifiers = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_$"))
        var start = probe
        while start > 0 {
            let ch = source.character(at: start - 1)
            if let scalar = Unicode.Scalar(ch), identifiers.contains(scalar) {
                start -= 1
            } else {
                break
            }
        }
        var end = probe
        while end < source.length {
            let ch = source.character(at: end)
            if let scalar = Unicode.Scalar(ch), identifiers.contains(scalar) {
                end += 1
            } else {
                break
            }
        }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    func replaceMultiSelections(with replacement: String) {
        guard hasMultiSelections else { return }
        let previousText = text ?? ""
        let mutable = NSMutableString(string: previousText)
        let ordered = multiSelections.sorted { $0.location > $1.location }
        var nextCarets: [NSRange] = []
        for range in ordered {
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: mutable.length))
            guard safe.location != NSNotFound else { continue }
            mutable.replaceCharacters(in: safe, with: replacement)
            nextCarets.append(NSRange(location: safe.location + (replacement as NSString).length, length: 0))
        }
        let updated = mutable as String
        text = updated
        invalidateLineNumberCache()
        nextCarets.sort { $0.location < $1.location }
        multiSelections = nextCarets
        selectedRange = nextCarets.last ?? selectedRange
        setNeedsDisplay()
        columnTextDidChange?()
    }

    private func drawMultiSelections() {
        guard hasMultiSelections else { return }
        let fillColor = UIColor.systemTeal.withAlphaComponent(0.30)
        fillColor.setFill()
        for range in multiSelections where !NSEqualRanges(range, selectedRange) {
            guard range.length > 0,
                  let start = position(from: beginningOfDocument, offset: range.location),
                  let end = position(from: start, offset: range.length),
                  let textRange = textRange(from: start, to: end)
            else { continue }
            for selectionRect in selectionRects(for: textRange) where !selectionRect.rect.isNull {
                UIRectFill(selectionRect.rect)
            }
        }
        // Zero-length carets get a thin vertical bar.
        for range in multiSelections where range.length == 0 {
            guard let start = position(from: beginningOfDocument, offset: range.location) else { continue }
            let caret = caretRect(for: start)
            UIRectFill(CGRect(x: caret.minX, y: caret.minY, width: 2, height: max(caret.height, font?.lineHeight ?? 14)))
        }
    }

    func selectAllFast() {
        clearColumnSelection()
        clearMultiSelections()
        // Scintilla's Editor::SelectAll stores the range (0, length) and
        // invalidates only the visible client rect. It does not lay out the
        // document and it does not scroll. Setting UITextView.selectedRange
        // to that same range forces TextKit to build a selection rect for
        // every glyph, which is the remaining Command-A hitch.
        let allRange = NSRange(location: 0, length: textStorage.length)
        isSelectingAllFast = true
        captureViewportAnchor()
        let heldOffset = contentOffset
        if textStorage.length >= EditorPerformance.virtualSelectAllUTF16Length {
            virtualSelectionRange = allRange
            onVirtualSelectionChanged?(allRange)
            setNeedsDisplay()
        } else {
            virtualSelectionRange = nil
            selectedRange = allRange
        }
        if abs(contentOffset.y - heldOffset.y) > 1 || abs(contentOffset.x - heldOffset.x) > 1 {
            applyPreservedContentOffset(heldOffset)
        }
        // Keep the guard through the remainder of the current run loop so a
        // deferred selection callback cannot start the expensive column scan.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if abs(self.contentOffset.y - heldOffset.y) > 1 || abs(self.contentOffset.x - heldOffset.x) > 1 {
                self.applyPreservedContentOffset(heldOffset)
            }
            self.isSelectingAllFast = false
        }
    }

    /// Paints the virtual whole-document selection for the visible lines only.
    /// This is the same cost model as Scintilla's `EditView::DrawLine`: the
    /// selection is two integers, and only the viewport is filled.
    private func drawVirtualSelection() {
        guard let range = virtualSelectionRange, range.length > 0, textStorage.length > 0 else { return }
        let visibleRect = CGRect(origin: contentOffset, size: bounds.size)
        let containerRect = visibleRect.offsetBy(dx: -textContainerInset.left, dy: -textContainerInset.top)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        guard glyphRange.length > 0 else { return }
        let visibleChars = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        let intersection = NSIntersectionRange(range, visibleChars)
        guard intersection.length > 0 else { return }
        let paintGlyphs = layoutManager.glyphRange(forCharacterRange: intersection, actualCharacterRange: nil)
        guard paintGlyphs.length > 0 else { return }
        (tintColor ?? UIColor.systemBlue).withAlphaComponent(0.28).setFill()
        layoutManager.enumerateEnclosingRects(
            forGlyphRange: paintGlyphs,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
            in: textContainer
        ) { rect, _ in
            UIRectFill(rect.offsetBy(dx: self.textContainerInset.left, dy: self.textContainerInset.top))
        }
    }

    func clearVirtualSelection(notify: Bool = true) {
        guard virtualSelectionRange != nil else { return }
        virtualSelectionRange = nil
        setNeedsDisplay()
        if notify { onVirtualSelectionChanged?(nil) }
    }

    override func selectAll(_ sender: Any?) {
        selectAllFast()
    }

    override func copy(_ sender: Any?) {
        if virtualSelectionRange != nil {
            UIPasteboard.general.string = text
            return
        }
        if hasMultiSelections {
            let source = text as NSString
            UIPasteboard.general.string = multiSelections.map { range in
                guard NSMaxRange(range) <= source.length else { return "" }
                return source.substring(with: range)
            }.joined(separator: "\n")
            return
        }
        guard let selection = columnSelection else {
            super.copy(sender)
            return
        }
        let source = text as NSString
        UIPasteboard.general.string = selection.ranges.map { range in
            guard NSMaxRange(range) <= source.length else { return "" }
            return source.substring(with: range)
        }.joined(separator: "\n")
    }

    override func cut(_ sender: Any?) {
        if virtualSelectionRange != nil {
            replaceVirtualSelection(with: "")
            return
        }
        if hasMultiSelections {
            copy(sender)
            replaceMultiSelections(with: "")
            return
        }
        if hasColumnSelection {
            copy(sender)
            replaceColumnSelections(with: "")
            return
        }
        super.cut(sender)
    }

    override func paste(_ sender: Any?) {
        if virtualSelectionRange != nil {
            replaceVirtualSelection(with: UIPasteboard.general.string ?? "")
            return
        }
        if hasMultiSelections {
            replaceMultiSelections(with: UIPasteboard.general.string ?? "")
            return
        }
        if hasColumnSelection {
            replaceColumnSelections(with: UIPasteboard.general.string ?? "")
            return
        }
        super.paste(sender)
    }

    override func deleteBackward() {
        if virtualSelectionRange != nil {
            replaceVirtualSelection(with: "")
            return
        }
        if hasMultiSelections {
            // Empty carets delete one character before each caret; ranges
            // delete their contents — same model as multi-cursor editors.
            let adjusted = multiSelections.map { range -> NSRange in
                if range.length > 0 { return range }
                let location = max(0, range.location - 1)
                return NSRange(location: location, length: range.location - location)
            }
            multiSelections = adjusted
            replaceMultiSelections(with: "")
            return
        }
        if hasColumnSelection {
            replaceColumnSelections(with: "")
            return
        }
        super.deleteBackward()
    }

    override func insertText(_ text: String) {
        if virtualSelectionRange != nil {
            replaceVirtualSelection(with: text)
            return
        }
        if hasMultiSelections {
            replaceMultiSelections(with: text)
            return
        }
        super.insertText(text)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if virtualSelectionRange != nil || hasColumnSelection || hasMultiSelections {
            if action == #selector(copy(_:))
                || action == #selector(cut(_:))
                || action == #selector(deleteBackward)
                || action == #selector(paste(_:)) {
                return true
            }
        }
        return super.canPerformAction(action, withSender: sender)
    }

    private func replaceVirtualSelection(with replacement: String) {
        guard let range = virtualSelectionRange else { return }
        let sourceLength = (text as NSString).length
        guard range.location == 0, range.length == sourceLength else {
            clearVirtualSelection()
            return
        }
        guard let start = position(from: beginningOfDocument, offset: 0),
              let end = position(from: start, offset: sourceLength),
              let textRange = textRange(from: start, to: end)
        else { return }
        replace(textRange, withText: replacement)
        clearVirtualSelection()
        selectedRange = NSRange(location: (replacement as NSString).length, length: 0)
    }

    func replaceColumnSelections(with replacement: String) {
        guard let selection = columnSelection, !selection.ranges.isEmpty else { return }
        let previousText = text ?? ""
        let replacementLines = replacement.components(separatedBy: .newlines)
        let distributesLines = replacementLines.count == selection.ranges.count
        let firstLine = TextStatistics.lineAndColumn(
            in: previousText,
            utf16Location: selection.ranges.first?.location ?? 0
        ).line - 1
        let lastLine = TextStatistics.lineAndColumn(
            in: previousText,
            utf16Location: selection.ranges.last?.location ?? 0
        ).line - 1
        let mutable = NSMutableString(string: previousText)

        for (index, range) in selection.ranges.enumerated().reversed() {
            guard range.location <= mutable.length else { continue }
            var value = distributesLines ? replacementLines[index] : replacement
            if !value.isEmpty {
                let lineRange = mutable.lineRange(for: NSRange(location: range.location, length: 0))
                let existingColumn = range.location - lineRange.location
                if existingColumn < selection.startColumn {
                    value = String(repeating: " ", count: selection.startColumn - existingColumn) + value
                }
            }
            let safeLength = min(range.length, mutable.length - range.location)
            mutable.replaceCharacters(in: NSRange(location: range.location, length: safeLength), with: value)
        }

        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreTextForColumnUndo(previousText)
        }
        text = mutable as String
        invalidateLineNumberCache()
        selectedRange = NSRange(
            location: min(selection.ranges.first?.location ?? 0, mutable.length),
            length: 0
        )
        let replacementIsUniform = !distributesLines || Set(replacementLines).count <= 1
        if replacementIsUniform {
            let insertedValue = distributesLines ? (replacementLines.first ?? "") : replacement
            let caretColumn = selection.startColumn + insertedValue.utf16.count
            let nextSelection = RectangularSelectionEngine.selection(
                in: mutable as String,
                startLine: firstLine,
                endLine: lastLine,
                startColumn: caretColumn,
                endColumn: caretColumn
            )
            setColumnSelection(nextSelection)
        } else {
            clearColumnSelection()
        }
        columnTextDidChange?()
    }

    /// Keep one search operation in the editor's native undo/redo stack.
    func applySearchReplacement(_ newText: String, selection: NSRange) {
        let previousText = text ?? ""
        let previousSelection = virtualSelectionRange ?? selectedRange
        undoManager?.registerUndo(withTarget: self) { target in
            target.applySearchReplacement(previousText, selection: previousSelection)
        }
        undoManager?.setActionName("替换")
        let savedDelegate = delegate
        delegate = nil
        clearVirtualSelection(notify: false)
        clearColumnSelection()
        text = newText
        let length = (newText as NSString).length
        let start = min(max(0, selection.location), length)
        selectedRange = NSRange(location: start, length: min(max(0, selection.length), length - start))
        delegate = savedDelegate
        columnTextDidChange?()
    }

    private func restoreTextForColumnUndo(_ restoredText: String) {
        let currentText = text ?? ""
        undoManager?.registerUndo(withTarget: self) { target in
            target.restoreTextForColumnUndo(currentText)
        }
        text = restoredText
        invalidateLineNumberCache()
        selectedRange = NSRange(location: min(selectedRange.location, (restoredText as NSString).length), length: 0)
        clearColumnSelection()
        columnTextDidChange?()
    }

    private func drawColumnSelection() {
        guard let selection = columnSelection else { return }
        let fillColor = UIColor.systemGreen.withAlphaComponent(0.28)
        fillColor.setFill()

        for range in selection.ranges {
            guard
                let start = position(from: beginningOfDocument, offset: range.location),
                let end = position(from: start, offset: range.length),
                let textRange = textRange(from: start, to: end)
            else { continue }

            if range.length == 0 {
                let caret = caretRect(for: start)
                UIRectFill(CGRect(x: caret.minX, y: caret.minY, width: 2, height: max(caret.height, font?.lineHeight ?? 14)))
            } else {
                for selectionRect in selectionRects(for: textRange) where !selectionRect.rect.isNull {
                    UIRectFill(selectionRect.rect)
                }
            }
        }
    }

    func invalidateLineNumberCache() {
        lineNumberCacheIsValid = false
        setNeedsDisplay()
    }

    func markdownViewportPosition() -> MarkdownScrollPosition {
        rebuildLineNumberCacheIfNeeded()
        guard textStorage.length > 0 else { return MarkdownScrollPosition() }
        let y = max(0, contentOffset.y - textContainerInset.top)
        let glyph = layoutManager.glyphIndex(for: CGPoint(x: textContainer.lineFragmentPadding, y: y), in: textContainer)
        let character = min(textStorage.length - 1, layoutManager.characterIndexForGlyph(at: glyph))
        let line = logicalLineNumber(atUTF16Offset: character)
        let start = cachedLineStarts[line - 1]
        let end = line < cachedLineStarts.count ? cachedLineStarts[line] : textStorage.length
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: max(1, end - start)), actualCharacterRange: nil)
        let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let fraction = min(1, max(0, (y - bounds.minY) / max(1, bounds.height)))
        let extent = max(0, contentSize.height - self.bounds.height + adjustedContentInset.bottom)
        return MarkdownScrollPosition(sourceLine: Double(line) + Double(fraction), progress: extent > 0 ? Double(max(0, contentOffset.y) / extent) : 0)
    }

    func scrollToMarkdownPosition(_ position: MarkdownScrollPosition) {
        rebuildLineNumberCacheIfNeeded()
        let index = min(cachedLineStarts.count - 1, max(0, Int(position.sourceLine) - 1))
        let start = cachedLineStarts[index]
        let end = index + 1 < cachedLineStarts.count ? cachedLineStarts[index + 1] : textStorage.length
        var y: CGFloat = 0
        if end > start {
            let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: end - start), actualCharacterRange: nil)
            let bounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            y = bounds.minY + CGFloat(position.sourceLine - floor(position.sourceLine)) * bounds.height + textContainerInset.top
        }
        let maximum = max(0, contentSize.height - bounds.height + adjustedContentInset.bottom)
        // Do not snap with progress — large Markdown previews send continuous
        // progress while the scrollbar is dragged, and the old 0 / 0.9999
        // clamps yanked the editor to the top or bottom mid-drag.
        setContentOffset(CGPoint(x: contentOffset.x, y: min(maximum, max(0, y))), animated: false)
    }

    private func rebuildLineNumberCacheIfNeeded() {
        guard !lineNumberCacheIsValid else { return }
        var starts = [0]
        starts.reserveCapacity(max(1, (text as NSString).length / 40))
        for (index, character) in text.utf16.enumerated() {
            if character == 10 {
                starts.append(index + 1)
            }
        }
        cachedLineStarts = starts
        lineNumberCacheIsValid = true
    }
}

/// Transparent control layered over the line-number gutter.  A plain
/// `UITapGestureRecognizer` on a clear UIView is unreliable on Mac Catalyst:
/// UIScrollView/UITextView's editing recognizers can win the hit-test and the
/// visible fold mark then appears inert.  UIControl's touch-up-inside path is
/// dispatched by UIKit before those editing gestures, so it remains reliable
/// for mouse clicks on large documents as well.
private final class FoldGutterTapView: UIControl {
    var onTap: ((CGPoint) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        guard let touch else { return }
        onTap?(touch.location(in: self))
    }
}

private extension Array where Element == Int {
    func partitioningIndex(where belongsInSecondPartition: (Int) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let middle = low + (high - low) / 2
            if belongsInSecondPartition(self[middle]) {
                high = middle
            } else {
                low = middle + 1
            }
        }
        return low
    }
}

struct MarkdownScrollRequest {
    let documentID: UUID
    let position: MarkdownScrollPosition
}

extension Notification.Name {
    static let markdownEditorDidScroll = Self("NotepadPlus.markdownEditorDidScroll")
    static let markdownPreviewDidScroll = Self("NotepadPlus.markdownPreviewDidScroll")
    static let markdownCopyRequested = Self("NotepadPlus.markdownCopyRequested")
}
