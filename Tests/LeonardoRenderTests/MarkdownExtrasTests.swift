#if os(macOS)
import AppKit
import CryptoKit
import LeonardoCore
import XCTest
import WebKit
@testable import LeonardoRender

@MainActor
final class MarkdownExtrasTests: XCTestCase {
    func testGuidedSigningLocationsMatchRenderedNestedRubricsInWebKit() async throws {
        let document = LeonardoDocument(
            body: """
            - Checklist
                - Nested {{field:sig}}

            Ordinary paragraph
                Continued {{field:sig}}

                Literal code {{field:sig}}

            Use `<code>` for a literal example.

            Last {{field:sig}}
            """,
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "nested-rubrics", title: "Nested rubrics", kind: .form, revision: 1,
                    signing: LeonardoSigningDeclaration(positions: [.init(id: "signer", label: "Signer")])
                ),
                fields: ["sig": .init(type: .rubric, signerPosition: "signer")]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        let session = try LeonardoGuidedSigningSession(document: document, at: Date())
        let targets = try session.targets(for: "signer", document: document)
        var configuration = MarkdownPreviewConfiguration()
        configuration.allowsLeonardoFormat = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('[data-leonardo-field-target]') ? '1' : '0'", in: web)
        let rendered = try await evaluate("""
            Array.from(document.querySelectorAll('[data-leonardo-field-target]')).map(
              node => node.dataset.leonardoFieldTarget
            ).join(',')
            """, in: web)
        XCTAssertEqual(rendered, "sig#0,sig#1,sig#2")
        XCTAssertEqual(rendered, targets.map { "\($0.fieldID)#\($0.occurrence)" }.joined(separator: ","))
        let inList = try await evaluate("document.querySelector('li li [data-leonardo-field-target]')?.dataset.leonardoFieldTarget", in: web)
        XCTAssertEqual(inList, "sig#0")
        let parity = try await evaluate("""
            window.LeonardoForms.hasFieldTarget('sig', 0, 3)
            && !window.LeonardoForms.hasFieldTarget('sig', 0, 2)
            """, in: web)
        XCTAssertEqual(parity, "1")
        let code = try await evaluate("document.querySelector('pre code')?.textContent.trim()", in: web)
        XCTAssertEqual(code, "Literal code {{field:sig}}")
    }

    func testSigningPlanRequiresRenderedVisibleTargetsForBothSigners() async throws {
        let declaration = LeonardoSigningDeclaration(positions: [
            .init(id: "owner", label: "Owner"), .init(id: "witness", label: "Witness")
        ])
        let document = LeonardoDocument(
            body: "Owner {{field:sig}}\n\nWitness {{field:second}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: .init(id: "plan-visibility", title: "Plan", kind: .form,
                                revision: 1, signing: declaration),
                fields: [
                    "sig": .init(type: .rubric, signerPosition: "owner"),
                    "second": .init(type: .rubric, signerPosition: "witness")
                ]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        var configuration = MarkdownPreviewConfiguration()
        configuration.allowsLeonardoFormat = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.getElementById('leonardo-field-second-0') ? '1' : '0'", in: web)
        let counts = ["sig": 1, "second": 1]
        let complete = await host.hasSigningFieldTargets(counts, source: source)
        XCTAssertTrue(complete)
        _ = try await evaluate("""
            document.getElementById('leonardo-field-second-0').parentElement.hidden = true;
            true
            """, in: web)
        let hidden = await host.hasSigningFieldTargets(counts, source: source)
        XCTAssertFalse(hidden)
        _ = try await evaluate("document.getElementById('leonardo-field-second-0').remove(); true", in: web)
        let missing = await host.hasSigningFieldTargets(counts, source: source)
        XCTAssertFalse(missing)
    }

    func testSigningSnapshotIncludesTheResponsiveAssetSelectedByWebKit() async throws {
        let document = LeonardoDocument(
            body: #"<picture><source srcset="selected.png" type="image/png"><img src="fallback.png"></picture>"#,
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: .init(id: "picture-signing", title: "Picture signing", kind: .form,
                                revision: 1, signing: .init(positions: [.init(id: "signer", label: "Signer")])),
                fields: ["sig": .init(type: .rubric, signerPosition: "signer")]
            )
        )
        var withTarget = document
        withTarget.body += "\n\n{{field:sig}}"
        let source = try LeonardoFormatParser.serialize(withTarget)
        let image = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN/QAAAAASUVORK5CYII="
        ))
        let selected = LeonardoSigningResource(reference: "selected.png", bytes: image)
        let fallback = LeonardoSigningResource(reference: "fallback.png", bytes: image)
        let snapshot = try LeonardoSigningSnapshot.capture(document: withTarget, resources: [selected, fallback], at: Date())
        let virtualRoot = URL(fileURLWithPath: "/signed-image-fixture", isDirectory: true)
        var config = MarkdownPreviewConfiguration(localAssetRoot: virtualRoot, memoryAssets: MarkdownMemoryAssets(files: [
            selected.reference: image, fallback.reference: image
        ]), allowsRemoteImages: false)
        config.allowsLeonardoFormat = true
        let (host, window) = makeHost(content: source, config: config, baseURL: virtualRoot)
        window.orderFront(nil)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))
        try await waitFor("document.querySelector('picture img') ? '1' : '0'", in: web)
        _ = try await evaluate("document.querySelector('picture img').loading = 'eager'", in: web)
        try await waitFor("document.querySelector('picture img')?.naturalWidth > 0 ? '1' : '0'", in: web)
        let selectedPath = try await evaluate("new URL(document.querySelector('picture img').currentSrc).pathname", in: web)
        XCTAssertEqual(selectedPath, "/selected.png")
        XCTAssertTrue(snapshot.resources.contains { $0.reference == String(selectedPath.dropFirst()) })
        let decoded = await host.hasRenderedLocalImages(["selected.png", "fallback.png"])
        XCTAssertTrue(decoded)
        let outsideSeal = await host.hasRenderedLocalImages(["fallback.png"])
        XCTAssertFalse(outsideSeal)
    }

    func testMacPreviewRejectsSamePathImageReplacementUntilItDisplaysNewBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a&b.png").resolvingSymlinksInPath()
        let original = try signingTestPNG(red: 1, blue: 0)
        let replacement = try signingTestPNG(red: 0, blue: 1)
        XCTAssertNotEqual(original, replacement)
        try original.write(to: file)
        var config = MarkdownPreviewConfiguration(localAssetRoot: directory, allowsRemoteImages: false)
        config.allowedLocalImageFiles = [file]
        let (host, window) = makeHost(content: #"<img src="a&amp;b.png">"#, config: config, baseURL: directory)
        window.orderFront(nil)
        defer { host.teardown(); window.close() }

        let originalDigest = [file: Data(SHA256.hash(data: original))]
        let replacementDigest = [file: Data(SHA256.hash(data: replacement))]
        let matchedOriginal = await host.hasReviewedSigningImages(originalDigest, includesEmbeddedImages: false)
        XCTAssertTrue(matchedOriginal)
        try replacement.write(to: file, options: [.atomic])
        let acceptedUnseenBytes = await host.hasReviewedSigningImages(replacementDigest, includesEmbeddedImages: false)
        XCTAssertFalse(acceptedUnseenBytes)

        host.reloadSigningImagePreview()
        let reviewedNewBytes = await host.hasReviewedSigningImages(replacementDigest, includesEmbeddedImages: false)
        XCTAssertTrue(reviewedNewBytes)

        try Data("not a PNG".utf8).write(to: file, options: [.atomic])
        host.reloadSigningImagePreview()
        let acceptedCorrupt = await host.hasReviewedSigningImages(
            [file: Data(SHA256.hash(data: Data("not a PNG".utf8)))], includesEmbeddedImages: false
        )
        XCTAssertFalse(acceptedCorrupt)
    }

    func testEmbeddedSigningImagesNeedSuccessfulDecodingEvenWithoutExternalResources() async throws {
        let valid = try signingTestPNG(red: 0, blue: 1).base64EncodedString()
        for (data, expected) in [(valid, true), ("AAAA", false)] {
            let source = "![Inline](data:image/png;base64,\(data))"
            let (host, window) = makeHost(content: source, config: MarkdownPreviewConfiguration(allowsRemoteImages: false))
            window.orderFront(nil)
            defer { host.teardown(); window.close() }
            let decoded = await host.hasRenderedLocalImages([], includesEmbeddedImages: true)
            XCTAssertEqual(decoded, expected)
        }
    }

    private func signingTestPNG(red: CGFloat, blue: CGFloat) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let image = try XCTUnwrap(context.makeImage())
        return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    func testGuidedRubricsDisplayOnlyVerifiedInkAndLeaveStandaloneRubricsAlone() async throws {
        let ink = LeonardoRubric(strokes: [LeonardoInkStroke(
            color: "#000000", width: 2, style: .solid,
            points: [LeonardoInkPoint(x: 1, y: 2), LeonardoInkPoint(x: 4, y: 5)]
        )])
        let authored = try JSONDecoder().decode(LeonardoJSONValue.self, from: JSONEncoder().encode(ink))
        let document = LeonardoDocument(
            body: "{{field:assigned}} {{field:withDefault}} {{field:standalone}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "guided-ink", title: "Guided ink", kind: .form, revision: 1,
                    signing: LeonardoSigningDeclaration(positions: [.init(id: "signer", label: "Signer")])
                ),
                fields: [
                    "assigned": .init(type: .rubric, signerPosition: "signer"),
                    "withDefault": .init(type: .rubric, defaultValue: authored, signerPosition: "signer"),
                    "standalone": .init(type: .rubric, defaultValue: authored)
                ],
                values: ["assigned": authored]
            )
        )
        let source = try LeonardoFormatParser.serialize(document)
        var config = MarkdownPreviewConfiguration()
        config.allowsLeonardoFormat = true
        let output = """
            Array.from(document.querySelectorAll('[data-leonardo-field-target]')).map(node =>
              node.querySelector('.leonardo-field-output svg') ? node.dataset.leonardoFieldTarget : ''
            ).filter(Boolean).join(',')
            """

        let (pending, pendingWindow) = makeHost(content: source, config: config)
        defer { pending.teardown(); pendingWindow.close() }
        let pendingWeb = try XCTUnwrap(webView(of: pending))
        try await waitFor("document.querySelectorAll('[data-leonardo-field-target]').length === 3 ? '1' : '0'", in: pendingWeb)
        let pendingInk = try await evaluate(output, in: pendingWeb)
        XCTAssertEqual(pendingInk, "standalone#0")

        config.guidedSigningRubricOverlays = ["assigned#0": ink]
        let (verified, verifiedWindow) = makeHost(content: source, config: config)
        defer { verified.teardown(); verifiedWindow.close() }
        let verifiedWeb = try XCTUnwrap(webView(of: verified))
        try await waitFor("document.querySelectorAll('[data-leonardo-field-target]').length === 3 ? '1' : '0'", in: verifiedWeb)
        let verifiedInk = try await evaluate(output, in: verifiedWeb)
        XCTAssertEqual(verifiedInk, "assigned#0,standalone#0")
    }

    func testFootnotesCalloutsAndTablesRenderTogetherInWebKit() async throws {
        let source = """
        # Extra syntax

        A local source is cited here.[^source] The same source is cited again.[^source]

        > [!WARNING]
        > Keep the source definition in the Markdown document.

        | Key | Value |
        | --- | --- |
        | Local | Ready |

        [^source]: The source is **offline** and remains editable.
        """
        var configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        configuration.allowsEditing = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('.markdown-footnotes') && document.querySelector('.markdown-callout-warning') && document.querySelector('.table-viewport table') ? '1' : '0'", in: web)
        let referenceCount = try await evaluate("document.querySelectorAll('.markdown-footnote-ref').length", in: web)
        let backreferenceCount = try await evaluate("document.querySelectorAll('.markdown-footnote-backref').length", in: web)
        let emphasizedText = try await evaluate("document.querySelector('.markdown-footnotes strong')?.textContent", in: web)
        let calloutTitle = try await evaluate("document.querySelector('.markdown-callout-title')?.textContent", in: web)
        let calloutRole = try await evaluate("document.querySelector('.markdown-callout')?.getAttribute('role')", in: web)
        let footnoteEditors = try await evaluate("document.querySelectorAll('.markdown-footnotes [contenteditable]').length", in: web)
        let calloutEditors = try await evaluate("document.querySelectorAll('.markdown-callout [contenteditable]').length", in: web)
        let currentSource = try await evaluate("window.LeonardoEditing.currentSource()", in: web)
        XCTAssertEqual(referenceCount, "2")
        XCTAssertEqual(backreferenceCount, "2")
        XCTAssertEqual(emphasizedText, "offline")
        XCTAssertEqual(calloutTitle, "Warning")
        XCTAssertEqual(calloutRole, "note")
        XCTAssertEqual(footnoteEditors, "0")
        XCTAssertEqual(calloutEditors, "0")
        XCTAssertEqual(currentSource, source)
        try await capture(web, name: "markdown-extras")
    }

    func testAllCalloutKindsAndSanitizationRenderSafely() async throws {
        let source = """
        > [!NOTE]
        > Note

        > [!TIP]
        > Tip

        > [!IMPORTANT]
        > Important

        > [!WARNING]
        > Warning

        > [!CAUTION]
        > <img src=x onerror="window.injected=true">
        """
        let configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelectorAll('.markdown-callout').length === 5 ? '1' : '0'", in: web)
        let kinds = try await evaluate("Array.from(document.querySelectorAll('.markdown-callout')).map(e => e.dataset.callout).join(',')", in: web)
        let unsafe = try await evaluate("document.querySelectorAll('.markdown-callout [onerror], .markdown-callout script').length", in: web)
        let injected = try await evaluate("typeof window.injected", in: web)
        XCTAssertEqual(kinds, "note,tip,important,warning,caution")
        XCTAssertEqual(unsafe, "0")
        XCTAssertEqual(injected, "undefined")
    }

    func testFootnotesInsideTablesAndIndentedDefinitionsRenderAndKeepSource() async throws {
        let source = """
        | Key | Value |
        | --- | --- |
        | Cite[^cell] | Ready |

           [^cell]: Table **note**
        """
        var configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        configuration.allowsEditing = true
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('.markdown-footnote-ref') && document.querySelector('.markdown-footnotes') ? '1' : '0'", in: web)
        let references = try await evaluate("document.querySelectorAll('.markdown-footnote-ref').length", in: web)
        let noteText = try await evaluate("document.querySelector('.markdown-footnotes strong')?.textContent", in: web)
        let table = try await evaluate("document.querySelector('.table-viewport table') ? '1' : '0'", in: web)
        let currentSource = try await evaluate("window.LeonardoEditing.currentSource()", in: web)
        XCTAssertEqual(references, "1")
        XCTAssertEqual(noteText, "note")
        XCTAssertEqual(table, "1")
        XCTAssertEqual(currentSource, source)
    }

    func testUndefinedFootnoteReferenceRemainsLiteral() async throws {
        let source = "An unresolved reference[^missing]."
        let configuration = MarkdownPreviewConfiguration(allowsMarkdownExtensions: true)
        let (host, window) = makeHost(content: source, config: configuration)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('#leonardo-markdown')?.textContent.includes('[^missing]') ? '1' : '0'", in: web)
        let footnotes = try await evaluate("document.querySelectorAll('.markdown-footnotes').length", in: web)
        let references = try await evaluate("document.querySelectorAll('.markdown-footnote-ref').length", in: web)
        XCTAssertEqual(footnotes, "0")
        XCTAssertEqual(references, "0")
    }

    func testDisabledExtrasKeepSourceReadableAsStandardMarkdown() async throws {
        let source = "> [!NOTE]\n> A regular blockquote when disabled.\n\nReference[^missing]"
        let (host, window) = makeHost(content: source)
        defer { host.teardown(); window.close() }
        let web = try XCTUnwrap(webView(of: host))

        try await waitFor("document.querySelector('blockquote') && document.querySelector('#leonardo-markdown') ? '1' : '0'", in: web)
        let extras = try await evaluate("typeof window.LeonardoMarkdownExtras", in: web)
        let generated = try await evaluate("document.querySelectorAll('.markdown-callout, .markdown-footnotes').length", in: web)
        let text = try await evaluate("document.querySelector('#leonardo-markdown')?.textContent || ''", in: web)
        XCTAssertEqual(extras, "undefined")
        XCTAssertEqual(generated, "0")
        XCTAssertTrue(text.contains("[!NOTE]"))
        XCTAssertTrue(text.contains("^missing"))
    }

    private func evaluate(_ script: String, in web: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            web.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: String(describing: result ?? "undefined"))
                }
            }
        }
    }

    private func waitFor(_ script: String, in web: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await evaluate(script, in: web)) == "1" { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("WebKit condition timed out: \(script)")
    }

    private func makeHost(
        content: String,
        config: MarkdownPreviewConfiguration = .default,
        baseURL: URL? = nil
    ) -> (MarkdownPreviewHost, NSWindow) {
        _ = NSApplication.shared
        let host = MarkdownPreviewHost(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.apply(content: content, baseURL: baseURL, configuration: config, onLinkActivation: nil, onScrollProgress: nil)
        return (host, window)
    }

    private func webView(of host: MarkdownPreviewHost) -> WKWebView? {
        host.subviews.compactMap { $0 as? WKWebView }.first
    }

    private func capture(_ web: WKWebView, name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["LEONARDO_VISUAL_EVIDENCE"] else { return }
        let png: Data = try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let tiff = image?.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let data = bitmap.representation(using: .png, properties: [:]) else {
                    continuation.resume(throwing: CocoaError(.fileReadUnknown))
                    return
                }
                continuation.resume(returning: data)
            }
        }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try png.write(to: root.appendingPathComponent(name + ".png"))
        let bitmap = NSBitmapImageRep(data: png)
        let browser = try await evaluate("navigator.userAgent", in: web)
        let metadata: [String: String] = [
            "head": ProcessInfo.processInfo.environment["EVIDENCE_SHA"] ?? "local working tree",
            "surface": "Markdown extras preview",
            "browser": browser,
            "viewportPoints": "1000x800",
            "imagePixels": "\(bitmap?.pixelsWide ?? 0)x\(bitmap?.pixelsHigh ?? 0)",
            "captureMode": "viewport",
            "capturedAtUTC": ISO8601DateFormatter().string(from: Date()),
            "state": "enabled footnotes, repeated references, warning callout and table; synthetic data"
        ]
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: root.appendingPathComponent(name + ".json"))
    }
}
#endif
