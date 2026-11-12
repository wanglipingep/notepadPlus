import AppKit
import WebKit

@main
@MainActor
final class MarkdownWebKitRegression: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var webView: WKWebView!
    var window: NSWindow!
    var lastPosition: [String: Double]?
    var messages = 0
    var started = false
    static var retained: MarkdownWebKitRegression?

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let runner = MarkdownWebKitRegression()
        retained = runner
        runner.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { fatalError("Preview WebKit regression timed out") }
        app.run()
    }

    static var source: String {
        "# 复制预览测试\n\n" + (1...100).map { "第\($0)段 **正文**，用于检验滚动同步。\n" }.joined(separator: "\n") + "\n```swift\nlet value = 42\n```"
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(WKUserScript(source: MarkdownPreviewBridge.script,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        config.userContentController.add(self, contentWorld: .defaultClient, name: "markdownViewport")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 700, height: 500), configuration: config)
        webView.navigationDelegate = self
        window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        webView.loadHTMLString(MarkdownHTMLRenderer.render(Self.source, theme: "light", emptyMessage: "空"), baseURL: nil)
    }

    func js(_ code: String, args: [String: Any] = [:]) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(code, arguments: args, in: nil, in: .defaultClient) { result in
                continuation.resume(with: result)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !started else { return }
        started = true
        Task {
            do {
                let all = try await js("return window.notepadMarkdown.copyText()") as! String
                precondition(all.contains("复制预览测试") && all.contains("let value = 42") && !all.contains("**正文**"))
                print("PASS: isolated app bridge works with page scripts disabled; full rendered text copies without Markdown markers")
                let selected = try await js("const range=document.createRange();range.selectNodeContents(document.querySelector('h1'));const selection=window.getSelection();selection.removeAllRanges();selection.addRange(range);return window.notepadMarkdown.copyText()") as! String
                precondition(selected == "复制预览测试")
                print("PASS: preview copy returns selected text when a selection exists")

                _ = try await js("window.getSelection().removeAllRanges();window.notepadMarkdown.scrollToPosition(83,0.4);await new Promise(r=>setTimeout(r,120));return true")
                let position = try await js("return window.notepadMarkdown.position()") as! [String: Double]
                let y = try await js("return window.scrollY") as! Double
                precondition(y > 0 && abs(position["line"]! - 83) < 1.1)
                let before = messages
                _ = try await js("window.scrollBy(0,180);await new Promise(r=>setTimeout(r,120));return true")
                precondition(messages > before && (lastPosition?["line"] ?? 0) > 83, "scroll messages=\(messages), before=\(before), last=\(String(describing: lastPosition))")
                print("PASS: source-line scrolling positions the preview and preview scrolling emits mapped source positions")

                let updated = MarkdownHTMLRenderer.render(Self.source.replacingOccurrences(of: "复制预览测试", with: "已实时更新"), theme: "dark", emptyMessage: "空")
                let result = try await js("window.notepadMarkdown.update(html,line,progress);await new Promise(r=>setTimeout(r,100));return {heading:document.querySelector('h1').innerText,theme:document.documentElement.className,line:window.notepadMarkdown.position().line,y:window.scrollY}",
                    args: ["html": updated, "line": lastPosition!["line"]!, "progress": lastPosition!["progress"]!]) as! [String: Any]
                precondition(result["heading"] as? String == "已实时更新" && result["theme"] as? String == "dark")
                precondition(abs((result["line"] as! Double) - lastPosition!["line"]!) < 1.1)
                print("PASS: in-place content/theme refresh keeps the viewport instead of returning to the top")
                print("WebKit integration: 4 regression scenarios passed")
                fflush(stdout)
                exit(0)
            } catch { fatalError("WebKit regression failed: \(error)") }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let position = message.body as? [String: Double] { lastPosition = position; messages += 1 }
    }
}
