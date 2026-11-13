import Foundation

/// Visual presets for the Markdown live preview pane.
public enum MarkdownPreviewStyle: String, CaseIterable, Identifiable, Sendable {
    case github
    case minimal
    case serif
    case compact
    case sepia
    case magazine
    case nord
    case dracula
    case ocean
    case forest
    case rose
    case slate
    case sunset
    case monokai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .github: "GitHub"
        case .minimal: "简洁"
        case .serif: "衬线阅读"
        case .compact: "紧凑"
        case .sepia: "羊皮纸"
        case .magazine: "杂志"
        case .nord: "Nord 雪原"
        case .dracula: "Dracula 紫夜"
        case .ocean: "海洋蓝"
        case .forest: "森林绿"
        case .rose: "玫瑰粉"
        case .slate: "石板灰"
        case .sunset: "落日橙"
        case .monokai: "Monokai"
        }
    }

    public var symbolName: String {
        switch self {
        case .github: "chevron.left.forwardslash.chevron.right"
        case .minimal: "square"
        case .serif: "text.book.closed"
        case .compact: "rectangle.compress.vertical"
        case .sepia: "newspaper"
        case .magazine: "doc.richtext"
        case .nord: "snowflake"
        case .dracula: "moon.stars"
        case .ocean: "water.waves"
        case .forest: "leaf"
        case .rose: "heart"
        case .slate: "square.fill"
        case .sunset: "sun.max"
        case .monokai: "paintbrush.pointed"
        }
    }
}

enum MarkdownHTMLRenderer {
    static func render(
        _ markdown: String,
        theme: String,
        style: String = MarkdownPreviewStyle.github.rawValue,
        emptyMessage: String
    ) -> String {
        let content = markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "<div class=\"empty\"><span>◇</span><p>\(escape(emptyMessage))</p></div>"
            : body(markdown)
        let forcedTheme = ["light", "dark", "system"].contains(theme) ? theme : "system"
        let knownStyles = Set(MarkdownPreviewStyle.allCases.map(\.rawValue))
        let forcedStyle = knownStyles.contains(style) ? style : MarkdownPreviewStyle.github.rawValue
        return """
        <!doctype html>
        <html class="\(forcedTheme) style-\(forcedStyle)">
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
              --body-font: -apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC","Hiragino Sans GB",sans-serif;
              --body-size: 16px; --body-line: 1.72; --pad-y: 42px; --pad-x: 46px; --maxw: 920px;
              --radius: 10px; --h1-size: 2.15em; --h2-size: 1.55em;
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
            /* Style presets */
            html.style-minimal { --shadow:none; --canvas:var(--bg); --pad-y:28px; --pad-x:32px; --maxw:860px; --radius:0; }
            html.style-minimal .markdown-body { border:0; box-shadow:none; }
            html.style-minimal h1,html.style-minimal h2 { border-bottom:0; }
            html.style-serif { --body-font: Georgia,"Songti SC","STSong","Noto Serif SC",serif;
              --body-size:17.5px; --body-line:1.85; --pad-y:48px; --pad-x:52px; --maxw:760px;
              --accent:#0b6e4f; --quote:#f4f7f2; }
            html.dark.style-serif,html.system.style-serif { --accent:#6bcb9a; --quote:#14231c; }
            @media (prefers-color-scheme: dark) {
              html.system.style-serif { --accent:#6bcb9a; --quote:#14231c; }
            }
            html.style-serif h1,html.style-serif h2,html.style-serif h3 { font-family:var(--body-font); font-weight:650; }
            html.style-compact { --body-size:14.5px; --body-line:1.55; --pad-y:22px; --pad-x:24px; --maxw:1000px;
              --h1-size:1.7em; --h2-size:1.3em; --shadow:0 4px 16px rgba(27,31,36,.05); }
            html.style-compact h1,html.style-compact h2,html.style-compact h3,html.style-compact h4 { margin:1.1em 0 .45em; }
            html.style-compact p { margin:.55em 0; }
            html.style-sepia { --bg:#f4ecd8; --canvas:#e8dcc0; --fg:#433422; --muted:#7a6548;
              --border:#d2c19a; --soft-border:#e0d2b0; --accent:#9a5b2e; --accent-soft:#efe2c4;
              --code:#ebe0c6; --quote:#efe6cf; --shadow:0 10px 28px rgba(90,60,20,.12);
              --body-font:Georgia,"Songti SC","PingFang SC",serif; --body-line:1.8; }
            html.dark.style-sepia { --bg:#2a2218; --canvas:#1c1710; --fg:#e8dcc4; --muted:#b5a078;
              --border:#4a3c28; --soft-border:#3a2f20; --accent:#d4a574; --accent-soft:#3a2c1c;
              --code:#33291c; --quote:#322618; --shadow:0 14px 34px rgba(0,0,0,.4); }
            @media (prefers-color-scheme: dark) {
              html.system.style-sepia { --bg:#2a2218; --canvas:#1c1710; --fg:#e8dcc4; --muted:#b5a078;
                --border:#4a3c28; --soft-border:#3a2f20; --accent:#d4a574; --accent-soft:#3a2c1c;
                --code:#33291c; --quote:#322618; --shadow:0 14px 34px rgba(0,0,0,.4); }
            }
            html.style-magazine { --accent:#2563eb; --accent-soft:#dbeafe; --maxw:820px; --pad-y:52px; --pad-x:48px;
              --h1-size:2.55em; --body-line:1.78; --shadow:0 18px 48px rgba(37,99,235,.10); }
            html.dark.style-magazine { --accent:#60a5fa; --accent-soft:#1e3a5f; }
            @media (prefers-color-scheme: dark) {
              html.system.style-magazine { --accent:#60a5fa; --accent-soft:#1e3a5f; }
            }
            html.style-magazine h1 { border-bottom:3px solid var(--accent); letter-spacing:-.03em; }
            html.style-magazine h2 { border-bottom:0; color:var(--accent); }

            /* Color-forward palettes */
            html.style-nord { --bg:#eceff4; --canvas:#e5e9f0; --fg:#2e3440; --muted:#4c566a;
              --border:#d8dee9; --soft-border:#e5e9f0; --accent:#5e81ac; --accent-soft:#d6e3f0;
              --code:#e5e9f0; --quote:#dbe4f0; --shadow:0 12px 32px rgba(46,52,64,.10); }
            html.dark.style-nord { --bg:#2e3440; --canvas:#242933; --fg:#eceff4; --muted:#9aa4b5;
              --border:#3b4252; --soft-border:#434c5e; --accent:#88c0d0; --accent-soft:#3b4a58;
              --code:#3b4252; --quote:#343b49; --shadow:0 16px 40px rgba(0,0,0,.4); }
            @media (prefers-color-scheme: dark) {
              html.system.style-nord { --bg:#2e3440; --canvas:#242933; --fg:#eceff4; --muted:#9aa4b5;
                --border:#3b4252; --soft-border:#434c5e; --accent:#88c0d0; --accent-soft:#3b4a58;
                --code:#3b4252; --quote:#343b49; --shadow:0 16px 40px rgba(0,0,0,.4); }
            }

            html.style-dracula { --bg:#f8f5ff; --canvas:#efeaf8; --fg:#2b2140; --muted:#6b5f86;
              --border:#ddd2f0; --soft-border:#e8e0f6; --accent:#bd93f9; --accent-soft:#efe4ff;
              --code:#efe8fb; --quote:#f3ecff; --shadow:0 14px 36px rgba(98,58,170,.12); }
            html.dark.style-dracula { --bg:#282a36; --canvas:#1e1f29; --fg:#f8f8f2; --muted:#a39bb8;
              --border:#44475a; --soft-border:#383a4a; --accent:#bd93f9; --accent-soft:#3b3354;
              --code:#343746; --quote:#323247; --shadow:0 16px 42px rgba(0,0,0,.45); }
            @media (prefers-color-scheme: dark) {
              html.system.style-dracula { --bg:#282a36; --canvas:#1e1f29; --fg:#f8f8f2; --muted:#a39bb8;
                --border:#44475a; --soft-border:#383a4a; --accent:#bd93f9; --accent-soft:#3b3354;
                --code:#343746; --quote:#323247; --shadow:0 16px 42px rgba(0,0,0,.45); }
            }
            html.style-dracula h2 { color:var(--accent); border-bottom-color:color-mix(in srgb,var(--accent) 35%,var(--border)); }

            html.style-ocean { --bg:#f2f9fc; --canvas:#e6f3f8; --fg:#163447; --muted:#4d7084;
              --border:#c5dde8; --soft-border:#d9ebf2; --accent:#0ea5e9; --accent-soft:#d7f0fb;
              --code:#e4f3fa; --quote:#e8f6fc; --shadow:0 12px 34px rgba(14,165,233,.12); }
            html.dark.style-ocean { --bg:#0b1c28; --canvas:#07131c; --fg:#d9eef8; --muted:#7fa8bd;
              --border:#1e3a4c; --soft-border:#163041; --accent:#38bdf8; --accent-soft:#123447;
              --code:#123041; --quote:#102b3b; --shadow:0 16px 40px rgba(0,0,0,.42); }
            @media (prefers-color-scheme: dark) {
              html.system.style-ocean { --bg:#0b1c28; --canvas:#07131c; --fg:#d9eef8; --muted:#7fa8bd;
                --border:#1e3a4c; --soft-border:#163041; --accent:#38bdf8; --accent-soft:#123447;
                --code:#123041; --quote:#102b3b; --shadow:0 16px 40px rgba(0,0,0,.42); }
            }

            html.style-forest { --bg:#f3f8f2; --canvas:#e7f0e5; --fg:#1f3324; --muted:#58705c;
              --border:#c9dbc8; --soft-border:#dce8da; --accent:#2f9e44; --accent-soft:#d7efd9;
              --code:#e3efe1; --quote:#e8f4e7; --shadow:0 12px 32px rgba(47,158,68,.12); }
            html.dark.style-forest { --bg:#142018; --canvas:#0d1611; --fg:#dceadf; --muted:#8eaa94;
              --border:#2a3d30; --soft-border:#213328; --accent:#69db7c; --accent-soft:#1d3a26;
              --code:#1b2e22; --quote:#18291f; --shadow:0 16px 40px rgba(0,0,0,.42); }
            @media (prefers-color-scheme: dark) {
              html.system.style-forest { --bg:#142018; --canvas:#0d1611; --fg:#dceadf; --muted:#8eaa94;
                --border:#2a3d30; --soft-border:#213328; --accent:#69db7c; --accent-soft:#1d3a26;
                --code:#1b2e22; --quote:#18291f; --shadow:0 16px 40px rgba(0,0,0,.42); }
            }

            html.style-rose { --bg:#fff5f8; --canvas:#fdecef; --fg:#4a2433; --muted:#8a5a6c;
              --border:#f0c9d6; --soft-border:#f7dde5; --accent:#e64980; --accent-soft:#fbd5e3;
              --code:#fce8ef; --quote:#fceef3; --shadow:0 12px 34px rgba(230,73,128,.12); }
            html.dark.style-rose { --bg:#2a1520; --canvas:#1d0e16; --fg:#f8dde7; --muted:#c48ea4;
              --border:#4a2840; --soft-border:#3a1f32; --accent:#f783ac; --accent-soft:#4a2238;
              --code:#3a1c2d; --quote:#351a29; --shadow:0 16px 40px rgba(0,0,0,.42); }
            @media (prefers-color-scheme: dark) {
              html.system.style-rose { --bg:#2a1520; --canvas:#1d0e16; --fg:#f8dde7; --muted:#c48ea4;
                --border:#4a2840; --soft-border:#3a1f32; --accent:#f783ac; --accent-soft:#4a2238;
                --code:#3a1c2d; --quote:#351a29; --shadow:0 16px 40px rgba(0,0,0,.42); }
            }

            html.style-slate { --bg:#f8fafc; --canvas:#eef2f6; --fg:#1e293b; --muted:#64748b;
              --border:#d5dde7; --soft-border:#e4eaf1; --accent:#475569; --accent-soft:#e2e8f0;
              --code:#eef2f7; --quote:#f1f5f9; --shadow:0 10px 28px rgba(30,41,59,.08); }
            html.dark.style-slate { --bg:#1e293b; --canvas:#0f172a; --fg:#e2e8f0; --muted:#94a3b8;
              --border:#334155; --soft-border:#273548; --accent:#94a3b8; --accent-soft:#2b3a4f;
              --code:#273548; --quote:#243247; --shadow:0 16px 40px rgba(0,0,0,.42); }
            @media (prefers-color-scheme: dark) {
              html.system.style-slate { --bg:#1e293b; --canvas:#0f172a; --fg:#e2e8f0; --muted:#94a3b8;
                --border:#334155; --soft-border:#273548; --accent:#94a3b8; --accent-soft:#2b3a4f;
                --code:#273548; --quote:#243247; --shadow:0 16px 40px rgba(0,0,0,.42); }
            }

            html.style-sunset { --bg:#fff7f1; --canvas:#ffefe3; --fg:#4a2a16; --muted:#8a6144;
              --border:#f0d0b8; --soft-border:#f7e2d2; --accent:#f97316; --accent-soft:#ffe0c7;
              --code:#ffead8; --quote:#fff0e4; --shadow:0 12px 34px rgba(249,115,22,.14); }
            html.dark.style-sunset { --bg:#2a1a12; --canvas:#1c100b; --fg:#ffe6d4; --muted:#c49a78;
              --border:#4a3224; --soft-border:#3a271c; --accent:#fb923c; --accent-soft:#4a2b18;
              --code:#3a2418; --quote:#332116; --shadow:0 16px 40px rgba(0,0,0,.42); }
            @media (prefers-color-scheme: dark) {
              html.system.style-sunset { --bg:#2a1a12; --canvas:#1c100b; --fg:#ffe6d4; --muted:#c49a78;
                --border:#4a3224; --soft-border:#3a271c; --accent:#fb923c; --accent-soft:#4a2b18;
                --code:#3a2418; --quote:#332116; --shadow:0 16px 40px rgba(0,0,0,.42); }
            }
            html.style-sunset h1 { border-bottom:2px solid var(--accent); }

            html.style-monokai { --bg:#f7f7f3; --canvas:#eeeeea; --fg:#272822; --muted:#6e6d5d;
              --border:#d6d6cb; --soft-border:#e4e4db; --accent:#a6e22e; --accent-soft:#e8f5c8;
              --code:#efefe8; --quote:#f0f3e4; --shadow:0 12px 32px rgba(39,40,34,.10); }
            html.dark.style-monokai { --bg:#272822; --canvas:#1d1e19; --fg:#f8f8f2; --muted:#a8a890;
              --border:#3e3d32; --soft-border:#33342c; --accent:#a6e22e; --accent-soft:#33401f;
              --code:#2f3028; --quote:#2c2d24; --shadow:0 16px 42px rgba(0,0,0,.45); }
            @media (prefers-color-scheme: dark) {
              html.system.style-monokai { --bg:#272822; --canvas:#1d1e19; --fg:#f8f8f2; --muted:#a8a890;
                --border:#3e3d32; --soft-border:#33342c; --accent:#a6e22e; --accent-soft:#33401f;
                --code:#2f3028; --quote:#2c2d24; --shadow:0 16px 42px rgba(0,0,0,.45); }
            }
            html.style-monokai h2 { color:var(--accent); border-bottom:0; }
            html.style-monokai a { color:#66d9ef; }
            html.dark.style-monokai a,html.system.style-monokai a { color:#66d9ef; }
            @media (prefers-color-scheme: dark) {
              html.system.style-monokai a { color:#66d9ef; }
            }

            * { box-sizing:border-box; }
            .markdown-body { -webkit-user-select:text; user-select:text; }
            html, body { margin:0; min-height:100%; background:var(--canvas); }
            body { color:var(--fg); font:var(--body-size)/var(--body-line) var(--body-font); }
            .markdown-body { max-width:var(--maxw); min-height:100vh; margin:0 auto; padding:var(--pad-y) var(--pad-x) 72px;
              background:var(--bg); box-shadow:var(--shadow); overflow-wrap:anywhere; border-radius:var(--radius); }
            h1,h2,h3,h4,h5,h6 { margin:1.7em 0 .65em; line-height:1.28; font-weight:700; letter-spacing:-.018em; }
            h1 { margin-top:.25em; padding-bottom:.38em; border-bottom:1px solid var(--border); font-size:var(--h1-size); }
            h2 { padding-bottom:.3em; border-bottom:1px solid var(--soft-border); font-size:var(--h2-size); }
            h3 { font-size:1.24em; } h4 { font-size:1.06em; }
            p { margin:.9em 0; } a { color:var(--accent); text-decoration:none; font-weight:550; }
            a:hover { text-decoration:underline; } strong { font-weight:700; }
            code { padding:.18em .38em; border:1px solid color-mix(in srgb,var(--border) 65%,transparent);
              border-radius:6px; background:var(--code); font:85%/1.55 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace; }
            pre { position:relative; margin:1.25em 0; padding:18px 20px; overflow:auto; border:1px solid var(--border);
              border-radius:var(--radius); background:var(--code); box-shadow:inset 3px 0 0 var(--accent); }
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
            img { display:block; max-width:100%; height:auto; margin:1.4em auto; border-radius:var(--radius); box-shadow:0 8px 24px rgba(0,0,0,.14); }
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
