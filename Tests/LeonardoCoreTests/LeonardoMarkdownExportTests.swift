import XCTest
@testable import LeonardoCore

final class LeonardoMarkdownExportTests: XCTestCase {
    func testFlattensValuesDefaultsAndRepeatedTokensWithoutMetadata() {
        let document = LeonardoDocument(body: "# {{field:name}}\n\n| Answer |\n| --- |\n| {{field:name}} |\n{{field:enabled}} {{field:count}} {{field:choice}} {{field:empty}}", metadata: LeonardoMetadata(
            fields: ["name": .init(), "enabled": .init(type: .checkbox), "count": .init(type: .number),
                     "choice": .init(type: .select, options: [.init(value: "a", label: "Option A")]), "empty": .init()],
            values: ["name": .string("Ada | <img src=x>"), "enabled": .boolean(false), "count": .number(42), "choice": .string("a")]))
        let result = LeonardoMarkdownExport.markdown(from: document)
        XCTAssertTrue(result.hasPrefix("# Ada &#124; &#60;img src&#61;x&#62;"))
        XCTAssertTrue(result.contains("false 42 Option A "))
        XCTAssertFalse(result.contains("{{field:"))
        XCTAssertFalse(result.contains("formatVersion"))
        XCTAssertEqual(document.metadata.values["count"], .number(42))
    }

    func testDefaultsNullAndMultilineLiteralValues() {
        let document = LeonardoDocument(body: "{{field:a}} / {{field:b}} / {{field:c}}", metadata: .init(
            fields: ["a": .init(defaultValue: .string("Default")), "b": .init(defaultValue: .string("Hidden")), "c": .init(type: .multiline)],
            values: ["b": .null, "c": .string("one\n**two**")]))
        XCTAssertEqual(LeonardoMarkdownExport.markdown(from: document), "Default /  / one<br>&#42;&#42;two&#42;&#42;")
    }

    func testRemovesLocalAndUnsupportedImagesAndKeepsRemoteImages() {
        let body = """
        ![local](assets/a.png) ![remote](https://example.com/a.png)
        ![inline](data:image/png;base64,abc) ![ref][picture]
        <img src='assets/x.jpg'> <img src="https://example.com/b.jpg">
        [picture]: assets/p.png
        """
        let result = LeonardoMarkdownExport.markdown(from: .init(body: body))
        XCTAssertFalse(result.contains("![local]"))
        XCTAssertFalse(result.contains("![inline]"))
        XCTAssertFalse(result.contains("![ref]"))
        XCTAssertFalse(result.contains("[picture]:"))
        XCTAssertFalse(result.contains("assets/p.png"))
        XCTAssertFalse(result.contains("src='assets"))
        XCTAssertTrue(result.contains("![remote](https://example.com/a.png)"))
        XCTAssertTrue(result.contains("<img src=\"https://example.com/b.jpg\">"))
    }

    func testReferenceImagesDropOrphanDefinitionsAndPreserveSharedLinks() {
        let body = """
        ![local][picture] ![collapsed][] ![shortcut] ![unsupported][ftp]
        ![remote][web] ![shared][shared]
        [ordinary][shared] [collapsedLink][] [shortcutLink]
        [picture]: assets/p.png
        [picture]: assets/duplicate.png
        [collapsed]: assets/c.png
        [shortcut]: file:///tmp/s.png
        [ftp]: ftp://example.com/unsupported.png
        [web]: https://example.com/keep.png
        [shared]: assets/shared.png
        ![collapsedLink][] ![shortcutLink]
        [collapsedLink]: assets/collapsed-shared.png
        [shortcutLink]: assets/shortcut-shared.png
        """
        let result = LeonardoMarkdownExport.markdown(from: .init(body: body))
        for reference in ["picture", "collapsed", "shortcut", "ftp"] {
            XCTAssertFalse(result.contains("[\(reference)]:"))
        }
        for path in ["assets/p.png", "assets/duplicate.png", "assets/c.png", "file:///tmp/s.png", "ftp://"] {
            XCTAssertFalse(result.contains(path))
        }
        XCTAssertTrue(result.contains("![remote][web]"))
        XCTAssertTrue(result.contains("[web]: https://example.com/keep.png"))
        XCTAssertFalse(result.contains("![shared]"))
        XCTAssertTrue(result.contains("[ordinary][shared]"))
        XCTAssertTrue(result.contains("[shared]: assets/shared.png"))
        XCTAssertTrue(result.contains("[collapsedLink]: assets/collapsed-shared.png"))
        XCTAssertTrue(result.contains("[shortcutLink]: assets/shortcut-shared.png"))
        XCTAssertFalse(result.contains("![collapsedLink]"))
        XCTAssertFalse(result.contains("![shortcutLink]"))
    }

    func testSelectWithEmptyLabelRetainsItsValue() {
        let document = LeonardoDocument(body: "{{field:a}}", metadata: .init(
            fields: ["a": .init(type: .select, options: [.init(value: "Answer", label: "")])],
            values: ["a": .string("Answer")]))
        XCTAssertEqual(LeonardoMarkdownExport.markdown(from: document), "Answer")
    }

    func testBalancedEscapedAndAngleImageDestinationsAreHandledAsWholeImages() {
        let paths = [
            "a_(b).png", "a_(b_(c)).png", #"a_\(b\).png"#, #"a_\(.png"#, #"a_\).png"#,
            "<a (b).png>", #"<a \> b.png>"#
        ]
        for path in paths {
            let local = path.hasPrefix("<") ? "<assets/" + path.dropFirst() : "assets/" + path
            let remote = path.hasPrefix("<") ? "<https://example.com/" + path.dropFirst() : "https://example.com/" + path
            for title in ["", " \"Caption\"", " 'Caption'", " (Caption)"] {
                let localImage = "![nested [alt]](\(local)\(title))"
                XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: "Before \(localImage) after")), "Before  after", localImage)
                let remoteImage = "![nested [alt]](\(remote)\(title))"
                XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: remoteImage)), remoteImage, remoteImage)
                let localReference = "![nested [alt]][picture]\n[picture]: \(local)\(title)\n"
                XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: localReference)), "\n", localReference)
                let remoteReference = "![nested [alt]][picture]\n[picture]: \(remote)\(title)\n"
                XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: remoteReference)), remoteReference, remoteReference)
            }
        }
        let reference = "![nested [alt]][picture]\n[picture]: assets/a_(b).png\n"
        XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: reference)), "\n")
    }

    func testEscapedReferenceLabelsAreRemovedOrPreservedForOrdinaryLinks() {
        let removed = #"![local][picture\]]"# + "\n" + #"[picture\]]: assets/a_(b).png"# + "\n"
        XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: removed)), "\n")
        let shared = #"![local][picture\]] [ordinary][picture\]]"# + "\n" + #"[picture\]]: assets/a_(b).png"# + "\n"
        let output = LeonardoMarkdownExport.markdown(from: .init(body: shared))
        XCTAssertFalse(output.contains("![local]"))
        XCTAssertTrue(output.contains(#"[ordinary][picture\]]"#))
        XCTAssertTrue(output.contains(#"[picture\]]: assets/a_(b).png"#))
    }

    func testHTMLImageQuotesEntitiesAndAlternativeTextAreReadAsWholeTags() {
        let local = #"<img alt="caption > src='https://example.com'" src="assets/a&gt;b.png">"#
        XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: "Before " + local + " after")), "Before  after")
        let remotes = [
            #"<img alt="caption > text" src="https://example.com/a>b.png">"#,
            #"<img src="https&#58;//example.com/a.png">"#,
            #"<img src="https&#X3A;//example.com/a.png">"#,
            #"<img alt="![literal](assets/a.png)" src="https://example.com/a.png">"#,
            #"<img alt="<img src='assets/literal.png'>" src="https://example.com/a.png">"#,
            #"<img alt="<!--" src="https://example.com/a.png">"#,
            #"<!-- ![literal](assets/a.png) <img src='assets/a.png'> -->"#,
            #"![alt <img src='assets/literal.png'>](https://example.com/a.png)"#
        ]
        for remote in remotes {
            XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: remote)), remote)
        }
    }

    func testCommentReferencesDoNotKeepRemovedImageDefinitions() {
        let body = "![local][picture] <!-- [ordinary][picture] -->\n[picture]: assets/a.png\n"
        XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: body)), " <!-- [ordinary][picture] -->\n")
    }

    func testUnrelatedReferenceDefinitionsRemainOrdinaryMarkdown() {
        let body = "[orphan]: assets/local.png\n"
        XCTAssertEqual(LeonardoMarkdownExport.markdown(from: .init(body: body)), body)
    }

    func testCodeExamplesRemainLiteral() {
        let body = """
        `{{field:a}} ![local](assets/a.png)`
        ```md
        {{field:a}} ![local](assets/a.png)
        ```
        {{field:a}}
        """
        let document = LeonardoDocument(body: body, metadata: .init(fields: ["a": .init(defaultValue: .string("Answer"))]))
        let result = LeonardoMarkdownExport.markdown(from: document)
        XCTAssertTrue(result.hasSuffix("Answer"))
        XCTAssertTrue(result.contains("`{{field:a}} ![local](assets/a.png)`"))
        XCTAssertTrue(result.contains("```md\n{{field:a}} ![local](assets/a.png)\n```"))
    }
}
