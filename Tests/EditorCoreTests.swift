import XCTest
@testable import NotepadPlusCore

final class EditorCoreTests: XCTestCase {
    func testLanguageDetection() {
        XCTAssertEqual(SyntaxLanguage.detect(filename: "ContentView.swift"), .swift)
        XCTAssertEqual(SyntaxLanguage.detect(filename: "package.json"), .json)
        XCTAssertEqual(SyntaxLanguage.detect(filename: "settings.jsonc"), .jsonc)
        XCTAssertEqual(SyntaxLanguage.detect(filename: "config.toml"), .toml)
        XCTAssertEqual(SyntaxLanguage.detect(filename: "README.md"), .markdown)
        XCTAssertEqual(SyntaxLanguage.detect(filename: "unknown"), .plainText)
    }

    func testJSONFormatterPrettyPrintsStrictJSON() throws {
        let result = try JSONFormatter.format(#"{"name":"NotepadPlus","items":[1,2]}"#)

        XCTAssertFalse(result.wasRepaired)
        XCTAssertEqual(
            result.text,
            """
            {
              "items" : [
                1,
                2
              ],
              "name" : "NotepadPlus"
            }
            """
        )
    }

    func testJSONFormatterRepairsBareKeyCommentsTrailingCommaAndSingleQuotes() throws {
        let source = """
        {
          // 同步配置
          "intfCode": "PUSH_PERSON_ESB",
          group: 'PERSON_CODE',
          "hierarchy": { "header": "PERSON_CODE", },
        }
        """

        let result = try JSONFormatter.format(source)
        XCTAssertTrue(result.wasRepaired)

        let data = try XCTUnwrap(result.text.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["intfCode"] as? String, "PUSH_PERSON_ESB")
        XCTAssertEqual(object["group"] as? String, "PERSON_CODE")
        XCTAssertEqual((object["hierarchy"] as? [String: String])?["header"], "PERSON_CODE")
    }

    func testJSONFormatterDoesNotTreatCommentMarkersInsideStringsAsComments() throws {
        let source = ##"{"url":"https://example.com/a//b","note":"/* 保留 */",key:"#value"}"##
        let result = try JSONFormatter.format(source)
        let data = try XCTUnwrap(result.text.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(object["url"], "https://example.com/a//b")
        XCTAssertEqual(object["note"], "/* 保留 */")
        XCTAssertEqual(object["key"], "#value")
    }

    func testLiteralSearchIsCaseInsensitiveAndWraps() throws {
        let text = "Hello hello HELLO"
        let options = SearchOptions()
        let matches = try SearchEngine.matches(in: text, query: "hello", options: options)
        XCTAssertEqual(matches.count, 3)
        XCTAssertEqual(try SearchEngine.nextMatch(in: text, query: "hello", after: 15, options: options)?.location, 0)
    }

    func testWholeWordSearch() throws {
        let text = "cat concatenate cat_2 cat."
        let matches = try SearchEngine.matches(
            in: text,
            query: "cat",
            options: SearchOptions(wholeWord: true)
        )
        XCTAssertEqual(matches.map(\.location), [0, 22])
    }

    func testRegexReplacement() throws {
        let result = try SearchEngine.replaceAll(
            in: "item-12 item-34",
            query: #"item-(\d+)"#,
            replacement: "value:$1",
            options: SearchOptions(regularExpression: true)
        )
        XCTAssertEqual(result.text, "value:12 value:34")
        XCTAssertEqual(result.count, 2)

        let single = try SearchEngine.replaceMatch(
            in: "name: Wang",
            range: NSRange(location: 0, length: 10),
            query: #"name: (\w+)"#,
            replacement: "user=$1",
            options: SearchOptions(regularExpression: true)
        )
        XCTAssertEqual(single.text, "user=Wang")
    }

    func testRegexDotMatchesNewlineAndBackwardWrap() throws {
        let options = SearchOptions(regularExpression: true, dotMatchesNewline: true)
        let matches = try SearchEngine.matches(in: "a\nb", query: "a.b", options: options)
        XCTAssertEqual(matches, [NSRange(location: 0, length: 3)])

        let text = "one two one"
        let previous = try SearchEngine.nextMatch(
            in: text,
            query: "one",
            after: 0,
            options: SearchOptions(),
            direction: .backward
        )
        XCTAssertEqual(previous?.location, 8)
    }

    func testExtendedModeEscapesAndLiteralModeRemainDistinct() throws {
        let text = "a\tb\na\\tb"
        let extended = SearchOptions(mode: .extended)
        XCTAssertEqual(try SearchEngine.matches(in: text, query: #"a\tb"#, options: extended), [NSRange(location: 0, length: 3)])
        XCTAssertEqual(try SearchEngine.matches(in: text, query: #"a\tb"#, options: SearchOptions()), [NSRange(location: 4, length: 4)])
        let result = try SearchEngine.replaceAll(in: text, query: #"\t"#, replacement: #"\n"#, options: extended)
        XCTAssertEqual(result.text, "a\nb\na\\tb")
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(SearchEngine.decodeExtended(#"\b00100000\o040\d032\x20\u4E2D"#), "    中")
        XCTAssertEqual(SearchEngine.decodeExtended(#"\uD83D\uDE00"#), "😀")
        XCTAssertEqual(SearchEngine.decodeExtended(#"\q\xZ1\u12\\"#), #"\q\xZ1\u12\"#)
    }

    func testRegexLineAnchorsAndZeroLengthReplacement() throws {
        let options = SearchOptions(regularExpression: true)
        let result = try SearchEngine.replaceAll(in: "one\ntwo\n三", query: "^", replacement: "> ", options: options)
        XCTAssertEqual(result.text, "> one\n> two\n> 三")
        XCTAssertEqual(result.count, 3)
        let match = try SearchEngine.replaceMatch(
            in: "one\ntwo", range: NSRange(location: 4, length: 0), query: "^", replacement: "> ", options: options
        )
        XCTAssertEqual(match.text, "one\n> two")
        XCTAssertEqual(match.replacementRange, NSRange(location: 4, length: 2))
        XCTAssertEqual(try SearchEngine.matches(in: "a\r\nb\rc", query: "^.", options: options).count, 3)
    }

    func testRegexReplacementBackreferencesNamesAndEscapes() throws {
        let result = try SearchEngine.replaceAll(
            in: "item-12 item-34",
            query: #"(?<kind>item)-(\d+)"#,
            replacement: #"$+{kind}:${2}/\2/$0/$&/$$/\$/\\\n"#,
            options: SearchOptions(regularExpression: true)
        )
        XCTAssertEqual(result.text, "item:12/12/item-12/item-12/$/$/\\\n item:34/34/item-34/item-34/$/$/\\\n")
        let optional = try SearchEngine.replaceAll(
            in: "b", query: "(a)?b", replacement: #"[$1]"#, options: SearchOptions(regularExpression: true)
        )
        XCTAssertEqual(optional.text, "[]")
    }

    func testSelectedReplacementIsLiteralInEveryMode() throws {
        let selection = "$1\\folder\n中😀\t\0"
        for mode in SearchMode.allCases {
            let options = SearchOptions(mode: mode)
            let replacement = SearchEngine.literalReplacement(selection, options: options)
            let result = try SearchEngine.replaceAll(in: "old old", query: "old", replacement: replacement, options: options)
            XCTAssertEqual(result.text, "\(selection) \(selection)", "Mode \(mode)")
        }
    }

    func testSelectionReplacementPreservesOutsideTextAndUnicodeOffsets() throws {
        let text = "😀 cat cat cat 尾"
        let result = try SearchEngine.replaceAll(
            in: text, query: "cat", replacement: "猫咪",
            options: SearchOptions(), in: NSRange(location: 7, length: 3)
        )
        XCTAssertEqual(result.text, "😀 cat 猫咪 cat 尾")
        XCTAssertEqual(result.count, 1)
        let narrowed = try SearchEngine.replaceAll(
            in: "aaa", query: "aa", replacement: "x",
            options: SearchOptions(), in: NSRange(location: 1, length: 2)
        )
        XCTAssertEqual(narrowed.text, "ax")
        let single = try SearchEngine.replaceMatch(
            in: "aaa", range: NSRange(location: 1, length: 2), query: "aa", replacement: "x",
            options: SearchOptions(), in: NSRange(location: 1, length: 2)
        )
        XCTAssertEqual(single.text, "ax")
    }

    func testSelectionSearchPreservesLookaroundAndWordBoundaries() throws {
        let options = SearchOptions(regularExpression: true)
        let result = try SearchEngine.replaceAll(
            in: "prefix123suffix 123", query: #"(?<=prefix)\d+(?=suffix)"#, replacement: "<$0>",
            options: options, in: NSRange(location: 6, length: 3)
        )
        XCTAssertEqual(result.text, "prefix<123>suffix 123")
        XCTAssertEqual(try SearchEngine.matches(
            in: "scatter", query: "cat", options: SearchOptions(wholeWord: true), in: NSRange(location: 1, length: 3)
        ), [])
        XCTAssertEqual(try SearchEngine.matches(
            in: "abc", query: "^b", options: options, in: NSRange(location: 1, length: 1)
        ), [])
    }

    func testSingleReplacementKeepsFullDocumentRegexContext() throws {
        let options = SearchOptions(regularExpression: true)
        let result = try SearchEngine.replaceMatch(
            in: "prefix123suffix", range: NSRange(location: 6, length: 3),
            query: #"(?<=prefix)(\d+)(?=suffix)"#, replacement: "[$1]", options: options
        )
        XCTAssertEqual(result.text, "prefix[123]suffix")
        let invalidTarget = try SearchEngine.replaceMatch(
            in: "abc", range: NSRange(location: 1, length: 1), query: "^b", replacement: "x", options: options
        )
        XCTAssertEqual(invalidTarget.text, "abc")
    }

    func testEmptyAndInvalidSearchesDoNotModifyText() throws {
        XCTAssertEqual(try SearchEngine.replaceAll(in: "text", query: "", replacement: "x", options: SearchOptions()).text, "text")
        XCTAssertThrowsError(try SearchEngine.replaceAll(in: "text", query: "(", replacement: "x", options: SearchOptions(regularExpression: true)))
        XCTAssertEqual(try SearchEngine.replaceAll(
            in: "text", query: "text", replacement: "x", options: SearchOptions(),
            in: NSRange(location: NSNotFound, length: 1)
        ).count, 0)
        XCTAssertEqual(try SearchEngine.replaceAll(
            in: "text", query: "$", replacement: "x", options: SearchOptions(regularExpression: true),
            in: NSRange(location: NSNotFound, length: 1)
        ).text, "text")
    }

    func testRegexModeIgnoresWholeWordAndLiteralModeIgnoresDotAll() throws {
        XCTAssertEqual(try SearchEngine.matches(
            in: "catfish", query: "cat", options: SearchOptions(wholeWord: true, regularExpression: true)
        ).count, 1)
        XCTAssertEqual(try SearchEngine.matches(
            in: "a\nb", query: "a.b", options: SearchOptions(dotMatchesNewline: true)
        ).count, 0)
    }

    func testJSONFoldingFindsNestedMultilineContainersAndIgnoresStrings() {
        let source = """
        {
          "text": "a } [ b",
          "items": [
            { "id": 1 }
          ]
        }
        """
        let regions = JSONFolding.regions(in: source)
        XCTAssertNotNil(regions[1])
        XCTAssertNotNil(regions[3])
        XCTAssertGreaterThan(regions[1]?.length ?? 0, regions[3]?.length ?? 0)

        // Folding keeps the opening line visible, but contracts all child
        // lines through the matching closing delimiter (including the close
        // line), as Scintilla/Notepad++ does.
        let outer = try! XCTUnwrap(regions[1])
        let foldedOuter = (source as NSString).substring(with: outer)
        XCTAssertFalse(foldedOuter.hasPrefix("{"))
        XCTAssertTrue(foldedOuter.contains("\n}"))

        let array = try! XCTUnwrap(regions[3])
        let foldedArray = (source as NSString).substring(with: array)
        XCTAssertTrue(foldedArray.contains("]"))
    }

    func testJSONFoldingStopsAtMatchingClosingLineInsteadOfExtendingToEOF() {
        let source = """
        {
          "data": {
            "rows": [
              "a",
              "b"
            ],
            "tail": true
          }
        }
        """
        let regions = JSONFolding.regions(in: source)
        let rows = try! XCTUnwrap(regions[3])
        let foldedRows = (source as NSString).substring(with: rows)
        XCTAssertTrue(foldedRows.contains("]"))
        XCTAssertFalse(foldedRows.contains("\"tail\""))
        XCTAssertFalse(foldedRows.contains("\"data\""))
    }

    /// Regression coverage for the large `劳动信息表.json` shape: a short
    /// array nested in a very large document must only hide its own matching
    /// closing line.  In particular, the range must not run to EOF when the
    /// closing line is followed by more object members.
    func testJSONFoldingShortNestedArrayDoesNotConsumeFollowingMembers() throws {
        let source = """
        {
          "data": {
            "rows": [
              {
                "cascader": [
                  "F1suoj",
                  "2a7elB",
                  "Kz98vF"
                ],
                "tail": true
              }
            ],
            "afterRows": "still visible"
          }
        }
        """
        let regions = JSONFolding.regions(in: source)
        let cascaderLine = 5
        let cascader = try XCTUnwrap(regions[cascaderLine])
        let folded = (source as NSString).substring(with: cascader)
        XCTAssertTrue(folded.contains("Kz98vF"))
        XCTAssertTrue(folded.contains("]"))
        XCTAssertFalse(folded.contains("\"tail\""))
        XCTAssertFalse(folded.contains("afterRows"))
    }

    func testJSONValueEditingRemovesObjectMemberAndComma() throws {
        let source = "{\n  \"name\": \"demo\",\n  \"enabled\": true\n}"
        let caret = NSRange(location: (source as NSString).range(of: "true").location, length: 0)
        let range = JSONValueEditing.deletionRange(in: source, selection: caret)
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(range)), ",\n  \"enabled\": true")
    }

    func testJSONValueEditingRemovesArrayItemWithFollowingComma() throws {
        let source = "{\"items\":[1, 2, 3]}"
        let caret = NSRange(location: (source as NSString).range(of: "2").location, length: 0)
        let range = JSONValueEditing.deletionRange(in: source, selection: caret)
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(range)), "2,")
    }

    func testJSONValueEditingRemovesNestedContainerAsOneValue() throws {
        let source = "{\"meta\": {\"id\": 1}, \"active\": true}"
        let caret = NSRange(location: (source as NSString).range(of: "{\"id\"").location, length: 0)
        let range = JSONValueEditing.deletionRange(in: source, selection: caret)
        XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(range)), "\"meta\": {\"id\": 1},")
    }

    func testTextTransformations() {
        XCTAssertEqual(
            TextTransformation.removeDuplicateLines.apply(to: "b\na\nb"),
            "b\na"
        )
        XCTAssertEqual(
            TextTransformation.trimTrailingWhitespace.apply(to: "a  \n b\t"),
            "a\n b"
        )
    }

    func testLineAndColumnUsesUTF16Offsets() {
        let position = TextStatistics.lineAndColumn(in: "one\n😀x", utf16Location: 6)
        XCTAssertEqual(position.line, 2)
        XCTAssertEqual(position.column, 3)
    }

    func testSelectAllUsesUTF16RangeWithoutWalkingLines() {
        let source = String(repeating: "😀value\n", count: 10_000)
        let range = TextSelectionEngine.allRange(in: source)
        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, (source as NSString).length)
    }

    func testLineEditingMovesAndDuplicatesWholeLines() {
        let moved = LineEditingEngine.apply(
            .moveDown,
            to: "a\nb\nc",
            selection: NSRange(location: 2, length: 0),
            language: .plainText
        )
        XCTAssertEqual(moved.text, "a\nc\nb")
        XCTAssertEqual(moved.selection.location, 4)

        let duplicated = LineEditingEngine.apply(
            .duplicate,
            to: "a\nb\n",
            selection: NSRange(location: 2, length: 0),
            language: .plainText
        )
        XCTAssertEqual(duplicated.text, "a\nb\nb\n")
    }

    func testToggleCommentUsesLanguagePrefix() {
        let commented = LineEditingEngine.apply(
            .toggleComment,
            to: "def example():\n    pass",
            selection: NSRange(location: 0, length: 24),
            language: .python
        )
        XCTAssertEqual(commented.text, "# def example():\n    # pass")

        let uncommented = LineEditingEngine.apply(
            .toggleComment,
            to: commented.text,
            selection: commented.selection,
            language: .python
        )
        XCTAssertEqual(uncommented.text, "def example():\n    pass")
    }

    func testDocumentStatistics() {
        XCTAssertEqual(TextStatistics.lineCount(in: "one two\nthree"), 2)
        XCTAssertEqual(TextStatistics.wordCount(in: "one two\nthree"), 3)
        XCTAssertEqual(TextStatistics.characterCount(in: "😀"), 1)
        XCTAssertEqual(TextStatistics.byteCount(in: "😀"), 4)
    }

    func testSelectAllRangeUsesUTF16LengthForLargeDocuments() {
        let text = String(repeating: "第 200 行：内容😀\n", count: 50_000)
        let started = Date()
        let range = TextSelectionEngine.allRange(in: text)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(range.location, 0)
        XCTAssertEqual(range.length, (text as NSString).length)
        // This is intentionally a generous guard against accidentally
        // introducing a per-line scan into Command-A. It is not a benchmark.
        XCTAssertLessThan(elapsed, 0.25)
    }

    func testDocumentScrollPositionStoreKeepsDocumentsIndependent() {
        let store = DocumentScrollPositionStore()
        let first = UUID()
        let second = UUID()
        store.set(EditorScrollPosition(x: 0, y: 2_300, anchorLocation: 18_400, anchorPixelDelta: 4), for: first)
        store.set(EditorScrollPosition(x: 0, y: 90, anchorLocation: 120, anchorPixelDelta: 0), for: second)

        XCTAssertEqual(store.offset(for: first), EditorScrollPosition(x: 0, y: 2_300, anchorLocation: 18_400, anchorPixelDelta: 4))
        XCTAssertEqual(store.offset(for: second), EditorScrollPosition(x: 0, y: 90, anchorLocation: 120, anchorPixelDelta: 0))

        store.remove(for: first)
        XCTAssertNil(store.offset(for: first))
        XCTAssertEqual(store.offset(for: second)?.anchorLocation, 120)
    }

    func testViewportAnchorRoundTripsTheVisibleLine() {
        let inset = 12.0
        let lineHeight = 18.0
        let lineCount = 2_000
        let top = ViewportAnchorMath.capture(
            contentOffsetY: 0,
            insetTop: inset,
            lineHeight: lineHeight,
            lineCount: lineCount
        )
        XCTAssertEqual(top.line, 0)
        XCTAssertEqual(
            ViewportAnchorMath.contentOffsetY(line: top.line, pixelDelta: top.pixelDelta, insetTop: inset, lineHeight: lineHeight),
            0
        )

        // Line 310 (1-based) sits at index 309. A click or a tab switch must
        // come back to that line, not to the temporary end of an estimated
        // content size.
        let offset = inset + 309 * lineHeight + 3
        let middle = ViewportAnchorMath.capture(
            contentOffsetY: offset,
            insetTop: inset,
            lineHeight: lineHeight,
            lineCount: lineCount
        )
        XCTAssertEqual(middle.line, 309)
        XCTAssertEqual(middle.pixelDelta, 3, accuracy: 0.001)
        XCTAssertEqual(
            ViewportAnchorMath.contentOffsetY(line: middle.line, pixelDelta: middle.pixelDelta, insetTop: inset, lineHeight: lineHeight),
            offset,
            accuracy: 0.001
        )
    }

    func testColumnEditingPadsShortLinesAndSupportsOverwrite() {
        let inserted = ColumnEditingEngine.apply(
            to: "a\nlong\nx",
            startLine: 1,
            endLine: 3,
            column: 3,
            value: "|"
        )
        XCTAssertEqual(inserted.text, "a |\nlo|ng\nx |")

        let overwritten = ColumnEditingEngine.apply(
            to: "abc\ndef",
            startLine: 1,
            endLine: 2,
            column: 2,
            value: "X",
            overwrite: true
        )
        XCTAssertEqual(overwritten.text, "aXc\ndXf")
    }

    func testRectangularSelectionCreatesOneRangePerLine() {
        let selection = RectangularSelectionEngine.selection(
            in: "abcd\nxy\n12345",
            anchor: 1,
            head: 12
        )

        XCTAssertEqual(selection.startColumn, 1)
        XCTAssertEqual(selection.endColumn, 4)
        XCTAssertEqual(selection.ranges, [
            NSRange(location: 1, length: 3),
            NSRange(location: 6, length: 1),
            NSRange(location: 9, length: 3)
        ])
    }

    func testRectangularSelectionHandlesReverseDragAndShortLines() {
        let selection = RectangularSelectionEngine.selection(
            in: "a\nlong\n",
            anchor: 6,
            head: 1
        )

        XCTAssertEqual(selection.startColumn, 1)
        XCTAssertEqual(selection.endColumn, 4)
        XCTAssertEqual(selection.ranges, [
            NSRange(location: 1, length: 0),
            NSRange(location: 3, length: 3)
        ])
    }

    func testRectangularSelectionCanBeRebuiltForContinuousColumnTyping() {
        let selection = RectangularSelectionEngine.selection(
            in: "甲乙丙\n短\n12345",
            startLine: 0,
            endLine: 2,
            startColumn: 3,
            endColumn: 3
        )

        XCTAssertEqual(selection.startColumn, 3)
        XCTAssertEqual(selection.endColumn, 3)
        XCTAssertEqual(selection.ranges.count, 3)
        XCTAssertEqual(selection.ranges.map(\.length), [0, 0, 0])
    }

    func testScratchRecoverySurvivesStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadPlusRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let record = ScratchRecoveryRecord(
            id: id,
            title: "新建 1.md",
            content: "# 不能丢失\n重要内容",
            language: "markdown",
            encoding: "utf8",
            lineEnding: "lf"
        )
        try ScratchRecoveryStore(directoryURL: directory).save(record)

        let restored = ScratchRecoveryStore(directoryURL: directory).loadAll()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, record.id)
        XCTAssertEqual(restored.first?.title, record.title)
        XCTAssertEqual(restored.first?.content, record.content)
    }

    func testScratchRecoveryFallsBackToPreviousAtomicBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotepadPlusRecoveryBackupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let id = UUID()
        let store = ScratchRecoveryStore(directoryURL: directory)
        let original = ScratchRecoveryRecord(
            id: id,
            title: "新建 1",
            content: "第一版",
            language: "plainText",
            encoding: "utf8",
            lineEnding: "lf"
        )
        var latest = original
        latest.content = "第二版"
        latest.updatedAt = original.updatedAt.addingTimeInterval(1)
        try store.save(original)
        try store.save(latest)

        let primary = directory.appendingPathComponent("\(id.uuidString).recovery.json")
        try Data("broken".utf8).write(to: primary, options: .atomic)

        let restored = store.loadAll()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.id, original.id)
        XCTAssertEqual(restored.first?.content, original.content)
    }

    func testLargeFilePolicyTiersAndShedding() {
        XCTAssertEqual(
            LargeFilePolicy.tier(byteCount: 1_000, utf16Length: 1_000),
            .normal
        )
        XCTAssertEqual(
            LargeFilePolicy.tier(byteCount: 1_000, utf16Length: LargeFilePolicy.largeUTF16Threshold),
            .large
        )
        XCTAssertEqual(
            LargeFilePolicy.tier(byteCount: LargeFilePolicy.hugeByteThreshold, utf16Length: 1),
            .huge
        )
        XCTAssertTrue(LargeFilePolicy.disablesWordWrap(.huge))
        XCTAssertTrue(LargeFilePolicy.disablesSyntaxHighlight(.large, language: .swift))
        XCTAssertFalse(LargeFilePolicy.disablesSyntaxHighlight(.large, language: .json))
        XCTAssertTrue(LargeFilePolicy.disablesBracketMatch(.large))
        XCTAssertTrue(LargeFilePolicy.disablesJSONFolding(.huge))
    }

    func testFunctionListExtractsSwiftSymbols() {
        let source = """
        public final class Editor {
            func save(document: Document) {}
            private func load() {}
        }
        struct Document {}
        """
        let symbols = FunctionListEngine.symbols(in: source, language: .swift)
        XCTAssertTrue(symbols.contains(where: { $0.name == "Editor" }))
        XCTAssertTrue(symbols.contains(where: { $0.name == "save" }))
        XCTAssertTrue(symbols.contains(where: { $0.name == "load" }))
        XCTAssertTrue(symbols.contains(where: { $0.name == "Document" }))
    }

    func testBraceFoldingHidesInnerLines() {
        let source = """
        func sample() {
            let value = 1
            if value > 0 {
                print(value)
            }
        }
        """
        let regions = BraceFolding.regions(in: source)
        XCTAssertFalse(regions.isEmpty)
        XCTAssertNotNil(regions[1] ?? regions.values.first)
    }

    func testReleaseNotesParserPreservesVersionsSectionsAndItems() {
        let markdown = """
        # 版本更新记录

        ## 1.2（2026-09-02）

        ### Markdown 预览与稳定性

        - 修复实时预览空白。
        - 增加回归验证。

        ## 1.1 (2026-08-31)

        - 首个稳定版本。
        """

        let releases = ReleaseNotesParser.parse(markdown)
        XCTAssertEqual(releases.map(\.version), ["1.2", "1.1"])
        XCTAssertEqual(releases.first?.date, "2026-09-02")
        XCTAssertEqual(releases.first?.sections.first?.title, "Markdown 预览与稳定性")
        XCTAssertEqual(releases.first?.sections.first?.items.count, 2)
        XCTAssertEqual(releases.last?.sections.first?.title, "其他改进")
        XCTAssertEqual(releases.last?.sections.first?.items, ["首个稳定版本。"]) 
    }
}
