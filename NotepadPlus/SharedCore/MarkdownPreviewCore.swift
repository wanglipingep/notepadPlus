import Foundation

enum MarkdownHTMLRenderer {
    static func render(_ markdown: String, theme: String, emptyMessage: String) -> String {
        let content = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "<div class=\"empty\"><span>◇</span><p>\(escape(emptyMessage))</p></div>"
            : body(markdown)
        let forcedTheme = ["light", "dark", "system"].contains(theme) ? theme : "system"
        return """
        <!doctype html>
        <html class="\(forcedTheme)">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: light dark;
              --bg: #ffffff; --canvas: #f6f8fa; --fg: #24292f; --muted: #57606a;
              --border: #d8dee4; --soft-border: #eaeef2; --accent: #2da44e;
              --accent-soft: #dafbe1; --code: #f6f8fa; --quote: #f0fdf4;
              --shadow: 0 12px 35px rgba(27,31,36,.07);
            }
            html.dark { --bg:#0d1117; --canvas:#010409; --fg:#e6edf3; --muted:#8b949e;
              --border:#30363d; --soft-border:#21262d; --accent:#3fb950;
              --accent-soft:#12261a; --code:#161b22; --quote:#0f2117;
              --shadow:0 16px 42px rgba(0,0,0,.35); }
            @media (prefers-color-scheme: dark) {
              html.system { --bg:#0d1117; --canvas:#010409; --fg:#e6edf3; --muted:#8b949e;
                --border:#30363d; --soft-border:#21262d; --accent:#3fb950;
                --accent-soft:#12261a; --code:#161b22; --quote:#0f2117;
                --shadow:0 16px 42px rgba(0,0,0,.35); }
            }
            * { box-sizing:border-box; }
            .markdown-body { -webkit-user-select:text; user-select:text; }
            html, body { margin:0; min-height:100%; background:var(--canvas); }
            body { color:var(--fg); font:16px/1.72 -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB",sans-serif; }
            .markdown-body { max-width:920px; min-height:100vh; margin:0 auto; padding:42px 46px 72px;
              background:var(--bg); box-shadow:var(--shadow); overflow-wrap:anywhere; }
            h1,h2,h3,h4,h5,h6 { margin:1.7em 0 .65em; line-height:1.28; font-weight:700; letter-spacing:-.018em; }
            h1 { margin-top:.25em; padding-bottom:.38em; border-bottom:1px solid var(--border); font-size:2.15em; }
            h2 { padding-bottom:.3em; border-bottom:1px solid var(--soft-border); font-size:1.55em; }
            h3 { font-size:1.24em; } h4 { font-size:1.06em; }
            p { margin:.9em 0; } a { color:var(--accent); text-decoration:none; font-weight:550; }
            a:hover { text-decoration:underline; } strong { font-weight:700; }
            code { padding:.18em .38em; border:1px solid color-mix(in srgb,var(--border) 65%,transparent);
              border-radius:6px; background:var(--code); font:85%/1.55 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace; }
            pre { position:relative; margin:1.25em 0; padding:18px 20px; overflow:auto; border:1px solid var(--border);
              border-radius:10px; background:var(--code); box-shadow:inset 3px 0 0 var(--accent); }
            pre code { padding:0; border:0; background:transparent; font-size:13.5px; white-space:pre; }
            pre[data-language]:not([data-language=""])::after { content:attr(data-language); position:absolute; top:8px; right:10px;
              color:var(--muted); font:700 10px/1 ui-monospace,monospace; text-transform:uppercase; letter-spacing:.08em; }
            blockquote { margin:1.25em 0; padding:11px 18px; border-left:4px solid var(--accent); border-radius:0 8px 8px 0;
              color:var(--muted); background:var(--quote); }
            blockquote p { margin:.3em 0; } ul,ol { padding-left:1.75em; } li { margin:.32em 0; } li::marker { color:var(--accent); }
            .task { list-style:none; margin-left:-1.35em; } .task input { margin:0 .55em 0 0; accent-color:var(--accent); }
            table { display:block; width:max-content; max-width:100%; overflow:auto; margin:1.4em 0; border-spacing:0;
              border:1px solid var(--border); border-radius:9px; }
            th,td { min-width:110px; padding:9px 13px; border-right:1px solid var(--border); border-bottom:1px solid var(--border); text-align:left; }
            th { background:var(--code); font-weight:650; } tr:last-child td { border-bottom:0; } th:last-child,td:last-child { border-right:0; }
            tr:nth-child(even) td { background:color-mix(in srgb,var(--code) 55%,transparent); }
            img { display:block; max-width:100%; height:auto; margin:1.4em auto; border-radius:10px; box-shadow:0 8px 24px rgba(0,0,0,.14); }
            hr { height:1px; margin:2em 0; border:0; background:linear-gradient(90deg,transparent,var(--border) 12%,var(--border) 88%,transparent); }
            del { color:var(--muted); } ::selection { background:color-mix(in srgb,var(--accent) 30%,transparent); }
            .empty { display:grid; place-items:center; min-height:60vh; color:var(--muted); text-align:center; }
            .empty span { display:block; color:var(--accent); font-size:44px; } .empty p { max-width:320px; }
            @media (max-width:620px) { .markdown-body { padding:28px 24px 55px; } }
          </style>
        </head>
        <body><main class="markdown-body">\(content)</main></body>
        </html>
        """
    }

    private static func body(_ markdown: String) -> String {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output: [String] = []
        var paragraph: [String] = []
        var paragraphStart = 0
        var paragraphEnd = 0
        var codeStart = 0
        var listKind: String?
        var inCode = false
        var codeLanguage = ""
        var codeLines: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            output.append("<p \(sourceAttributes(paragraphStart, paragraphEnd))>\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
        }
        func closeList() {
            guard let kind = listKind else { return }
            output.append("</\(kind)>")
            listKind = nil
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inCode {
                if trimmed.hasPrefix("```") {
                    output.append("<pre \(sourceAttributes(codeStart, index)) data-language=\"\(escape(codeLanguage))\"><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    inCode = false; codeLines.removeAll(); codeLanguage = ""
                } else {
                    codeLines.append(line)
                }
                index += 1; continue
            }
            if trimmed.hasPrefix("```") {
                flushParagraph(); closeList(); inCode = true; codeStart = index
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1; continue
            }
            if trimmed.isEmpty {
                flushParagraph(); closeList(); index += 1; continue
            }
            if isTableHeader(at: index, lines: lines) {
                flushParagraph(); closeList()
                let tableStart = index
                let headers = tableCells(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count, lines[index].contains("|") && !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(tableCells(lines[index])); index += 1
                }
                output.append(table(headers: headers, rows: rows).replacingOccurrences(of: "<table>", with: "<table \(sourceAttributes(tableStart, index - 1))>")); continue
            }
            if let heading = heading(line) {
                flushParagraph(); closeList()
                output.append("<h\(heading.level) \(sourceAttributes(index, index))>\(inline(heading.text))</h\(heading.level)>")
                index += 1; continue
            }
            if trimmed.range(of: #"^([-*_])(?:\s*\1){2,}$"#, options: .regularExpression) != nil {
                flushParagraph(); closeList(); output.append("<hr \(sourceAttributes(index, index))>"); index += 1; continue
            }
            if trimmed.hasPrefix(">") {
                flushParagraph(); closeList()
                let quoteStart = index
                var quotes: [String] = []
                while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let quote = lines[index].trimmingCharacters(in: .whitespaces).dropFirst()
                    quotes.append(String(quote).trimmingCharacters(in: .whitespaces)); index += 1
                }
                output.append("<blockquote \(sourceAttributes(quoteStart, index - 1))><p>\(inline(quotes.joined(separator: " ")))</p></blockquote>")
                continue
            }
            if let item = listItem(line) {
                flushParagraph()
                if listKind != item.kind { closeList(); listKind = item.kind; output.append("<\(item.kind)>") }
                if let checked = item.checked {
                    output.append("<li \(sourceAttributes(index, index)) class=\"task\"><input type=\"checkbox\" disabled \(checked ? "checked" : "")>\(inline(item.text))</li>")
                } else {
                    output.append("<li \(sourceAttributes(index, index))>\(inline(item.text))</li>")
                }
                index += 1; continue
            }
            closeList()
            if paragraph.isEmpty { paragraphStart = index }
            paragraphEnd = index
            paragraph.append(trimmed); index += 1
        }
        flushParagraph(); closeList()
        if inCode {
            output.append("<pre \(sourceAttributes(codeStart, index)) data-language=\"\(escape(codeLanguage))\"><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
        }
        return output.joined(separator: "\n")
    }

    private static func sourceAttributes(_ start: Int, _ end: Int) -> String {
        "data-source-line=\"\(start + 1)\" data-source-end=\"\(max(start, end) + 1)\""
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(trimmed.dropFirst(hashes + 1)))
    }

    private static func listItem(_ line: String) -> (kind: String, text: String, checked: Bool?)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^[-+*]\s+"#, options: .regularExpression) != nil {
            var text = trimmed.replacingOccurrences(of: #"^[-+*]\s+"#, with: "", options: .regularExpression)
            if text.hasPrefix("[ ] ") { text.removeFirst(4); return ("ul", text, false) }
            if text.lowercased().hasPrefix("[x] ") { text.removeFirst(4); return ("ul", text, true) }
            return ("ul", text, nil)
        }
        if trimmed.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) != nil {
            return ("ol", trimmed.replacingOccurrences(of: #"^\d+[.)]\s+"#, with: "", options: .regularExpression), nil)
        }
        return nil
    }

    private static func isTableHeader(at index: Int, lines: [String]) -> Bool {
        guard index + 1 < lines.count, lines[index].contains("|") else { return false }
        let separator = lines[index + 1].trimmingCharacters(in: .whitespaces)
        return separator.range(of: #"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$"#, options: .regularExpression) != nil
    }

    private static func tableCells(_ line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func table(headers: [String], rows: [[String]]) -> String {
        let head = headers.map { "<th>\(inline($0))</th>" }.joined()
        let body = rows.map { row in "<tr>\(row.map { "<td>\(inline($0))</td>" }.joined())</tr>" }.joined()
        return "<table><thead><tr>\(head)</tr></thead><tbody>\(body)</tbody></table>"
    }

    private static func inline(_ raw: String) -> String {
        var codeTokens: [String] = []
        var value = escape(raw)
        value = replacing(#"`([^`]+)`"#, in: value) { match in
            codeTokens.append("<code>\(match[1])</code>")
            return "@@NPPCODE\(codeTokens.count - 1)@@"
        }
        value = replacing(#"!\[([^\]]*)\]\(([^\s)]+)(?:\s+&quot;[^&]*&quot;)?\)"#, in: value) {
            "<img src=\"\($0[2])\" alt=\"\($0[1])\">"
        }
        value = replacing(#"\[([^\]]+)\]\(([^\s)]+)(?:\s+&quot;[^&]*&quot;)?\)"#, in: value) {
            "<a href=\"\($0[2])\">\($0[1])</a>"
        }
        value = replacing(#"\*\*([^*]+)\*\*|__([^_]+)__"#, in: value) { "<strong>\($0[1].isEmpty ? $0[2] : $0[1])</strong>" }
        value = replacing(#"~~([^~]+)~~"#, in: value) { "<del>\($0[1])</del>" }
        value = replacing(#"(?<!\*)\*([^*]+)\*(?!\*)|(?<!_)_([^_]+)_(?!_)"#, in: value) { "<em>\($0[1].isEmpty ? $0[2] : $0[1])</em>" }
        for (index, token) in codeTokens.enumerated() {
            value = value.replacingOccurrences(of: "@@NPPCODE\(index)@@", with: token)
        }
        return value
    }

    private static func replacing(_ pattern: String, in input: String, transform: ([String]) -> String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return input }
        let source = input as NSString
        let matches = expression.matches(in: input, range: NSRange(location: 0, length: source.length))
        let result = NSMutableString(string: input)
        for match in matches.reversed() {
            let groups = (0..<match.numberOfRanges).map { index -> String in
                let range = match.range(at: index)
                return range.location == NSNotFound ? "" : source.substring(with: range)
            }
            result.replaceCharacters(in: match.range, with: transform(groups))
        }
        return result as String
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

/// Trusted bridge runs in WebKit's isolated client world. User Markdown stays
/// escaped and page JavaScript remains disabled.
enum MarkdownPreviewBridge {
    static let script = #"""
    (() => {
      let applying = false, scheduled = false, generation = 0;
      const blocks = () => [...document.querySelectorAll('[data-source-line]')];
      const top = element => element.getBoundingClientRect().top + window.scrollY;
      const extent = () => Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      function position() {
        const y = window.scrollY, nodes = blocks();
        let node = nodes[0];
        for (const candidate of nodes) {
          if (top(candidate) <= y + 1) node = candidate; else break;
        }
        if (!node) return {line: 1, progress: 0};
        const start = Number(node.dataset.sourceLine), end = Number(node.dataset.sourceEnd);
        const fraction = Math.max(0, Math.min(1, (y - top(node)) / Math.max(1, node.getBoundingClientRect().height)));
        return {line: start + fraction * (end - start + 1), progress: extent() ? y / extent() : 0};
      }
      function scrollToPosition(line, progress) {
        const nodes = blocks();
        let node = nodes[0];
        for (const candidate of nodes) {
          if (Number(candidate.dataset.sourceLine) <= line) node = candidate; else break;
        }
        let y = 0;
        if (node) {
          const start = Number(node.dataset.sourceLine), end = Number(node.dataset.sourceEnd);
          y = top(node) + Math.max(0, Math.min(1, (line - start) / (end - start + 1))) * node.getBoundingClientRect().height;
        } else if (extent() > 0 && Number.isFinite(progress)) {
          // Progress is only a fallback when source-line anchors are missing.
          // Never snap to 0 / end from progress during scrollbar drags — that
          // yank is what made large-document preview scrolling unusable.
          y = Math.max(0, Math.min(1, progress)) * extent();
        }
        applying = true;
        const token = ++generation;
        window.scrollTo(0, Math.max(0, Math.min(extent(), y)));
        // Hold longer so editor→preview echo cannot fight an in-progress drag.
        clearTimeout(window.__notepadMarkdownRelease);
        window.__notepadMarkdownRelease = setTimeout(() => {
          if (token === generation) applying = false;
        }, 180);
      }
      window.notepadMarkdown = {
        position, scrollToPosition,
        copyText: () => window.getSelection().toString() || document.querySelector('main').innerText,
        update: (html, line, progress) => {
          const parsed = new DOMParser().parseFromString(html, 'text/html');
          document.documentElement.className = parsed.documentElement.className;
          document.querySelector('main').innerHTML = parsed.querySelector('main').innerHTML;
          scrollToPosition(line, progress);
        }
      };
      window.addEventListener('scroll', () => {
        if (applying || scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
          scheduled = false;
          if (!applying) window.webkit.messageHandlers.markdownViewport.postMessage(position());
        });
      }, {passive: true});
      document.addEventListener('load', event => {
        if (event.target.tagName === 'IMG') window.webkit.messageHandlers.markdownViewport.postMessage(position());
      }, true);
    })();
    """#
}
