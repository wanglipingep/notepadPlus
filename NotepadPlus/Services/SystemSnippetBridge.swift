import Foundation
import UIKit
import Darwin
import CoreGraphics
import ObjectiveC

/// Raycast-style system paste / open helpers.
///
/// REA on Raycast.app: `PasteToFrontmostApplicationRequest`, `pasteToFrontmostApp`,
/// `lastFrontmostApplication`, `clipboardHistoryDirectPaste`, `CGEvent` key posting.
/// We keep a continuous `lastExternalFrontmost` (any app that is not us) so opening
/// Snippets / Clipboard from our own menu still pastes back to the prior caret.
enum SystemSnippetBridge {
    static let appKitHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/AppKit.framework/AppKit", RTLD_NOW)
    }()

    private static let applicationServicesHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
    }()

    /// Frontmost app at the moment the palette opened (may be ourselves).
    private(set) static var previousFrontmostBundleID: String?
    private(set) static var previousFrontmostPID: pid_t = 0

    /// Last non-NotepadPlus frontmost app — Raycast `lastFrontmostApplication`.
    private(set) static var lastExternalBundleID: String?
    private(set) static var lastExternalPID: pid_t = 0

    private static var trackingStarted = false
    private static var activateObserver: NSObjectProtocol?

    private static var ownBundleID: String {
        Bundle.main.bundleIdentifier ?? "com.wanglp.notepadplus"
    }

    // MARK: - Self detection (Catalyst may report `…~iosmac`)

    static func isSelfBundleID(_ bid: String?) -> Bool {
        guard let bid, !bid.isEmpty else { return false }
        let own = ownBundleID
        if bid == own { return true }
        if bid.hasPrefix(own) { return true }
        let normalized = bid.replacingOccurrences(of: "~iosmac", with: "")
        if normalized == own { return true }
        return bid.lowercased().contains("notepadplus")
    }

    static var previousAppIsSelf: Bool {
        isSelfBundleID(previousFrontmostBundleID)
    }

    static var pasteTargetIsSelf: Bool {
        let bid = pasteTargetBundleID
        return bid == nil || isSelfBundleID(bid)
    }

    private static var pasteTargetBundleID: String? {
        if let bid = previousFrontmostBundleID, !isSelfBundleID(bid) { return bid }
        return lastExternalBundleID
    }

    private static var pasteTargetPID: pid_t {
        if previousFrontmostPID > 0, !isSelfBundleID(previousFrontmostBundleID) {
            return previousFrontmostPID
        }
        return lastExternalPID
    }

    // MARK: - Continuous frontmost tracking

    @MainActor
    static func startFrontmostTracking() {
        guard !trackingStarted else { return }
        trackingStarted = true
        _ = appKitHandle
        refreshFrontmost(rememberExternal: true)

        // NSWorkspace notifications live on the workspace center, not .default.
        if let workspaceClass = NSClassFromString("NSWorkspace") as? NSObject.Type {
            let sharedSel = NSSelectorFromString("sharedWorkspace")
            if workspaceClass.responds(to: sharedSel),
               let shared = workspaceClass.perform(sharedSel)?.takeUnretainedValue() as? NSObject {
                let centerSel = NSSelectorFromString("notificationCenter")
                if shared.responds(to: centerSel),
                   let center = shared.perform(centerSel)?.takeUnretainedValue() as? NotificationCenter {
                    let name = Notification.Name("NSWorkspaceDidActivateApplicationNotification")
                    activateObserver = center.addObserver(
                        forName: name,
                        object: nil,
                        queue: .main
                    ) { _ in
                        refreshFrontmost(rememberExternal: true)
                    }
                }
            }
        }

        // Poll as a safety net — Catalyst activation notifications can be sparse.
        Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                refreshFrontmost(rememberExternal: true)
            }
        }
    }

    @discardableResult
    static func refreshFrontmost(rememberExternal: Bool) -> (bundleID: String?, pid: pid_t) {
        guard let app = frontmostRunningApplication() else {
            return (nil, 0)
        }
        let bid = bundleID(of: app)
        let pid = processID(of: app)
        if rememberExternal, !isSelfBundleID(bid) {
            lastExternalBundleID = bid
            lastExternalPID = pid
        }
        return (bid, pid)
    }

    static func captureFrontmostApplication() {
        let current = refreshFrontmost(rememberExternal: true)
        previousFrontmostBundleID = current.bundleID
        previousFrontmostPID = current.pid
    }

    // MARK: - Activate / open

    @discardableResult
    static func activatePreviousApplication() -> Bool {
        let pid = pasteTargetPID
        if pid > 0, activate(pid: pid) { return true }
        if let bid = pasteTargetBundleID, activate(bundleID: bid) { return true }
        return false
    }

    /// Open with the macOS default app (Excel / Word / Preview…), not NotepadPlus.
    @discardableResult
    static func openWithDefaultApplication(_ url: URL) -> Bool {
        guard appKitHandle != nil,
              let workspaceClass = NSClassFromString("NSWorkspace") as? NSObject.Type
        else {
            UIApplication.shared.open(url)
            return true
        }
        let sharedSel = NSSelectorFromString("sharedWorkspace")
        guard workspaceClass.responds(to: sharedSel),
              let shared = workspaceClass.perform(sharedSel)?.takeUnretainedValue() as? NSObject
        else {
            UIApplication.shared.open(url)
            return true
        }
        // openURL: is deprecated but reliable via runtime; prefer openURLs:withAppBundleIdentifier:…
        let openSel = NSSelectorFromString("openURL:")
        if let method = class_getInstanceMethod(object_getClass(shared), openSel) {
            typealias Fn = @convention(c) (AnyObject, Selector, NSURL) -> Bool
            let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            if fn(shared, openSel, url as NSURL) { return true }
        }
        let openFileSel = NSSelectorFromString("openFile:")
        if shared.responds(to: openFileSel),
           let result = shared.perform(openFileSel, with: url.path) {
            _ = result
            return true
        }
        UIApplication.shared.open(url)
        return true
    }

    // MARK: - Paste inject (Raycast DirectPaste)

    /// Write text, resign NotepadPlus, activate the remembered app, post ⌘V.
    @MainActor
    static func pasteIntoPreviousApplication(_ text: String) async {
        writePasteboard(text)
        promptAccessibilityIfNeeded()

        // Give the floating UI a moment to dismiss so we don't eat the keystroke.
        try? await Task.sleep(for: .milliseconds(80))

        if !pasteTargetIsSelf {
            resignSelf()
            try? await Task.sleep(for: .milliseconds(60))
            _ = activatePreviousApplication()
            // Wait for the target text field to become key again.
            try? await Task.sleep(for: .milliseconds(160))
        }
        postCommandV()
        // Second chance — some apps ignore the first synthetic paste.
        try? await Task.sleep(for: .milliseconds(40))
        postCommandV()
    }

    static func writePasteboard(_ text: String) {
        UIPasteboard.general.string = text
        guard appKitHandle != nil,
              let cls = NSClassFromString("NSPasteboard") as? NSObject.Type
        else { return }
        let generalSel = NSSelectorFromString("generalPasteboard")
        guard cls.responds(to: generalSel),
              let board = cls.perform(generalSel)?.takeUnretainedValue() as? NSObject
        else { return }
        let clearSel = NSSelectorFromString("clearContents")
        if board.responds(to: clearSel) { _ = board.perform(clearSel) }
        let setSel = NSSelectorFromString("setString:forType:")
        guard let method = class_getInstanceMethod(object_getClass(board), setSel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, NSString, NSString) -> Bool
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        _ = fn(board, setSel, text as NSString, "public.utf8-plain-text" as NSString)
        _ = fn(board, setSel, text as NSString, "NSStringPboardType" as NSString)
    }

    static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
            ?? CGEventSource(stateID: .hidSystemState)
        let keyCodeV: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCodeV, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    static var isTrustedForAccessibility: Bool {
        guard let sym = dlsym(applicationServicesHandle, "AXIsProcessTrusted") else { return false }
        typealias Fn = @convention(c) () -> Bool
        return unsafeBitCast(sym, to: Fn.self)()
    }

    @discardableResult
    static func promptAccessibilityIfNeeded() -> Bool {
        if isTrustedForAccessibility { return true }
        guard let promptSym = dlsym(applicationServicesHandle, "AXIsProcessTrustedWithOptions") else {
            return false
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        typealias Fn = @convention(c) (CFDictionary?) -> Bool
        return unsafeBitCast(promptSym, to: Fn.self)(options)
    }

    // MARK: - AppKit helpers

    private static func frontmostRunningApplication() -> NSObject? {
        guard appKitHandle != nil,
              let workspaceClass = NSClassFromString("NSWorkspace") as? NSObject.Type
        else { return nil }
        let sharedSel = NSSelectorFromString("sharedWorkspace")
        guard workspaceClass.responds(to: sharedSel),
              let shared = workspaceClass.perform(sharedSel)?.takeUnretainedValue() as? NSObject
        else { return nil }
        let frontSel = NSSelectorFromString("frontmostApplication")
        guard shared.responds(to: frontSel) else { return nil }
        return shared.perform(frontSel)?.takeUnretainedValue() as? NSObject
    }

    private static func bundleID(of app: NSObject) -> String? {
        let sel = NSSelectorFromString("bundleIdentifier")
        guard app.responds(to: sel) else { return nil }
        return app.perform(sel)?.takeUnretainedValue() as? String
    }

    private static func processID(of app: NSObject) -> pid_t {
        let sel = NSSelectorFromString("processIdentifier")
        guard let method = class_getInstanceMethod(object_getClass(app), sel) else { return 0 }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Int32
        return unsafeBitCast(method_getImplementation(method), to: Fn.self)(app, sel)
    }

    private static func activate(pid: pid_t) -> Bool {
        guard let cls = NSClassFromString("NSRunningApplication") as? NSObject.Type,
              let method = class_getClassMethod(cls, NSSelectorFromString("runningApplicationWithProcessIdentifier:"))
        else { return false }
        typealias Fn = @convention(c) (AnyClass, Selector, Int32) -> Unmanaged<NSObject>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let sel = NSSelectorFromString("runningApplicationWithProcessIdentifier:")
        guard let app = fn(cls, sel, pid)?.takeUnretainedValue() else { return false }
        return activate(app)
    }

    private static func activate(bundleID: String) -> Bool {
        guard let cls = NSClassFromString("NSRunningApplication") as? NSObject.Type,
              let method = class_getClassMethod(cls, NSSelectorFromString("runningApplicationsWithBundleIdentifier:"))
        else { return false }
        typealias Fn = @convention(c) (AnyClass, Selector, NSString) -> Unmanaged<NSArray>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        let sel = NSSelectorFromString("runningApplicationsWithBundleIdentifier:")
        guard let apps = fn(cls, sel, bundleID as NSString)?.takeUnretainedValue(),
              let app = apps.firstObject as? NSObject
        else { return false }
        return activate(app)
    }

    private static func activate(_ app: NSObject) -> Bool {
        let sel = NSSelectorFromString("activateWithOptions:")
        guard let method = class_getInstanceMethod(object_getClass(app), sel) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt) -> Bool
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        // NSApplicationActivateIgnoringOtherApps = 1 << 1
        return fn(app, sel, 1 << 1)
    }

    private static func resignSelf() {
        guard appKitHandle != nil,
              let appClass = NSClassFromString("NSApplication") as? NSObject.Type
        else { return }
        let sharedSel = NSSelectorFromString("sharedApplication")
        guard appClass.responds(to: sharedSel),
              let app = appClass.perform(sharedSel)?.takeUnretainedValue() as? NSObject
        else { return }
        let hideSel = NSSelectorFromString("hide:")
        if app.responds(to: hideSel) {
            _ = app.perform(hideSel, with: nil)
        }
    }
}

// MARK: - Global hotkey ⌥⌘S

@MainActor
final class SnippetGlobalHotKey {
    static let shared = SnippetGlobalHotKey()

    var onPressed: (() -> Void)?

    private var nsMonitor: AnyObject?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        SystemSnippetBridge.startFrontmostTracking()
        SystemSnippetBridge.promptAccessibilityIfNeeded()
        installNSEventMonitor()
    }

    private func installNSEventMonitor() {
        guard nsMonitor == nil,
              SystemSnippetBridge.appKitHandle != nil,
              let cls = NSClassFromString("NSEvent")
        else { return }

        let sel = NSSelectorFromString("addGlobalMonitorForEventsMatchingMask:handler:")
        guard let method = class_getClassMethod(cls, sel) else { return }

        let handlerBlock: @convention(block) (AnyObject) -> Void = { [weak self] event in
            let flags = Self.modifierFlags(of: event)
            guard flags & (1 << 19) != 0, flags & (1 << 20) != 0 else { return }
            guard Self.characters(of: event)?.lowercased() == "s" else { return }
            DispatchQueue.main.async { self?.onPressed?() }
        }

        typealias Fn = @convention(c) (AnyClass, Selector, UInt64, Any) -> Unmanaged<AnyObject>?
        let fn = unsafeBitCast(method_getImplementation(method), to: Fn.self)
        if let monitor = fn(cls, sel, 1 << 10, handlerBlock)?.takeRetainedValue() {
            nsMonitor = monitor
        }
    }

    private static func modifierFlags(of event: AnyObject) -> UInt {
        let sel = NSSelectorFromString("modifierFlags")
        guard let method = class_getInstanceMethod(object_getClass(event), sel) else { return 0 }
        typealias Fn = @convention(c) (AnyObject, Selector) -> UInt
        return unsafeBitCast(method_getImplementation(method), to: Fn.self)(event, sel)
    }

    private static func characters(of event: AnyObject) -> String? {
        let sel = NSSelectorFromString("charactersIgnoringModifiers")
        guard event.responds(to: sel) else { return nil }
        return event.perform(sel)?.takeUnretainedValue() as? String
    }
}
