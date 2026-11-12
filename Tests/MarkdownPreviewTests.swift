import XCTest
@testable import NotepadPlusCore

final class MarkdownPreviewTests: XCTestCase {
    func testBlocksMapToOriginalSourceLinesIncludingBlankLinesAndMultilineCode() {
        let markdown = "# 标题\n\n第一行\n第二行\n\n```swift\nlet value = 1\nprint(value)\n```\n\n- 项目一\n- 项目二\n\n> 引用\n> 继续"
        let html = MarkdownHTMLRenderer.render(markdown, theme: "light", emptyMessage: "空")
        XCTAssertTrue(html.contains("<h1 data-source-line=\"1\" data-source-end=\"1\">"))
        XCTAssertTrue(html.contains("<p data-source-line=\"3\" data-source-end=\"4\">"))
        XCTAssertTrue(html.contains("<pre data-source-line=\"6\" data-source-end=\"9\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"11\" data-source-end=\"11\">"))
        XCTAssertTrue(html.contains("<blockquote data-source-line=\"14\" data-source-end=\"15\">"))
        XCTAssertTrue(html.contains("user-select:text"))
    }

    func testTableTasksAndUnclosedCodeHaveSourceAnchors() {
        let markdown = "A | B\n--- | ---\none | two\n\n- [x] 完成\n\n```\n保留的代码"
        let html = MarkdownHTMLRenderer.render(markdown, theme: "dark", emptyMessage: "空")
        XCTAssertTrue(html.contains("<table data-source-line=\"1\" data-source-end=\"3\">"))
        XCTAssertTrue(html.contains("<li data-source-line=\"5\" data-source-end=\"5\" class=\"task\">"))
        XCTAssertTrue(html.contains("<pre data-source-line=\"7\""))
        XCTAssertTrue(html.contains("保留的代码</code>"))
    }

    func testRawHTMLCannotInjectScriptsAndEmptyMessageIsEscaped() {
        let html = MarkdownHTMLRenderer.render("<script>alert('x')</script>\n\n```html\n<b>代码</b>\n```", theme: "invalid\" onload=\"x", emptyMessage: "空")
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("&lt;b&gt;代码&lt;/b&gt;"))
        XCTAssertTrue(html.contains("<html class=\"system\">"))
        XCTAssertTrue(MarkdownHTMLRenderer.render(" \n", theme: "light", emptyMessage: "<空>").contains("&lt;空&gt;"))
    }

    func testViewportPositionRejectsInvalidNumbersAndClampsBounds() {
        XCTAssertEqual(MarkdownScrollPosition(sourceLine: .nan, progress: .infinity), MarkdownScrollPosition())
        XCTAssertEqual(MarkdownScrollPosition(sourceLine: -10, progress: -1), MarkdownScrollPosition())
        XCTAssertEqual(MarkdownScrollPosition(sourceLine: 42.5, progress: 2).progress, 1)
        XCTAssertEqual(MarkdownScrollPosition(sourceLine: 42.5, progress: 0.4).sourceLine, 42.5)
    }
}
