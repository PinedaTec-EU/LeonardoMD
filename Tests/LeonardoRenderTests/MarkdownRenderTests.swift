import Foundation
import CryptoKit
import Testing
@testable import LeonardoRender

struct MarkdownRenderTests {
    @Test
    func memoryAssetsOnlyServeSelectedImagePaths() throws {
        let bytes = Data([1, 2, 3])
        let assets = MarkdownMemoryAssets(files: ["docs/images/diagrama ñ.png": bytes, "private.txt": bytes])
        #expect(assets.data(for: try #require(URL(string: "leonardo-document://local/docs/images/diagrama%20%C3%B1.png"))) == bytes)
        for value in ["https://local/docs/images/diagrama%20%C3%B1.png", "leonardo-document://outside/docs/images/diagrama%20%C3%B1.png",
                      "leonardo-document://local/private.txt", "leonardo-document://local/missing.png",
                      "leonardo-document://local/docs/../private.png"] {
            #expect(assets.data(for: try #require(URL(string: value))) == nil)
        }
    }

    @Test
    func offlinePreviewDisallowsRemoteImageLoads() throws {
        let html = try MarkdownHTMLShell.make(content: "![remote](https://example.invalid/image.png)", baseURL: nil,
            configuration: MarkdownPreviewConfiguration(allowsRemoteImages: false))
        #expect(html.contains("img-src leonardo-document: data:;"))
        #expect(!html.contains("img-src leonardo-document: data: http:"))
    }

    @Test
    func packagedAssetsMatchRecordedHashesIncludingEmbeddedSanitizer() throws {
        let metadata = try #require(MarkdownResourceCatalog.url(forFile: "THIRD_PARTY_SOURCES.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        let packages = try #require(manifest["packages"] as? [[String: Any]])
        for package in packages {
            let files = try #require(package["files"] as? [String: String])
            for (path, expectedHash) in files {
                let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let url = try #require(MarkdownResourceCatalog.url(forFile: path)
                    ?? (path.hasPrefix("fonts/") ? MarkdownResourceCatalog.fontURL(named: fileName) : nil))
                let actualHash = SHA256.hash(data: try Data(contentsOf: url))
                    .map { String(format: "%02x", $0) }.joined()
                #expect(actualHash == expectedHash, "Packaged resource differs from recorded source: \(path)")
            }
        }
        let mermaidData = try #require(MarkdownResourceCatalog.data(for: .mermaid))
        let mermaid = try #require(String(data: mermaidData, encoding: .utf8))
        #expect(mermaid.contains("DOMPurify 3.4.16"))
        #expect(!mermaid.contains("DOMPurify 3.4.0"))
        #expect(!mermaid.contains("0.16.45"))
    }

    @Test
    func imageSymlinksMustRemainInsideAllowedAssetRoot() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let root = temporary.appendingPathComponent("assets", isDirectory: true)
        let outside = temporary.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let allowedImage = root.appendingPathComponent("allowed.png")
        let privateImage = outside.appendingPathComponent("private.png")
        try Data([1]).write(to: allowedImage)
        try Data([2]).write(to: privateImage)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.png"), withDestinationURL: allowedImage)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape.png"), withDestinationURL: privateImage)

        let allowed = MarkdownDocumentSchemeHandler.resolvedFileURL(
            baseDirectory: root, assetRoot: root,
            requestURL: try #require(URL(string: "leonardo-document://local/alias.png"))
        )
        let rejected = MarkdownDocumentSchemeHandler.resolvedFileURL(
            baseDirectory: root, assetRoot: root,
            requestURL: try #require(URL(string: "leonardo-document://local/escape.png"))
        )
        #expect(allowed == allowedImage.resolvingSymlinksInPath())
        #expect(rejected == nil)
    }

    @Test
    func optionalScriptsAreNotPartOfDisabledPreview() throws {
        let disabledResources = MarkdownResourceCatalog.resources(for: .default)
        let html = try MarkdownHTMLShell.make(
            content: "```mermaid\nflowchart TD\nA-->B\n```\n\n$x$",
            baseURL: nil,
            configuration: MarkdownPreviewConfiguration(allowsMermaid: false, allowsMath: false)
        )

        #expect(!html.contains("mermaid.min.js"))
        #expect(!html.contains("katex.min.js"))
        #expect(!html.contains("katex.min.css"))
        #expect(!disabledResources.contains(.mermaid))
        #expect(!disabledResources.contains(.katex))
        #expect(html.contains("\"allowsMermaid\":false"))
        #expect(html.contains("\"allowsMath\":false"))
    }

    @Test
    func enablingOneOptionalFeatureLoadsOnlyItsResources() throws {
        let mermaid = try MarkdownHTMLShell.make(
            content: "```mermaid\nflowchart TD\nA-->B\n```",
            baseURL: nil,
            configuration: MarkdownPreviewConfiguration(allowsMermaid: true, allowsMath: false)
        )
        let math = try MarkdownHTMLShell.make(
            content: "$$x^2$$",
            baseURL: nil,
            configuration: MarkdownPreviewConfiguration(allowsMermaid: false, allowsMath: true)
        )

        #expect(mermaid.contains("mermaid.min.js"))
        #expect(!mermaid.contains("katex.min.js"))
        #expect(math.contains("katex.min.js"))
        #expect(math.contains("katex.min.css"))
        #expect(!math.contains("mermaid.min.js"))

        let runtime = String(data: MarkdownResourceCatalog.data(for: .runtime) ?? Data(), encoding: .utf8) ?? ""
        #expect(runtime.contains("htmlLabels: false"))
        #expect(runtime.contains("securityLevel: \"strict\""))
        #expect(runtime.contains("installHeadingAnchors"))
        #expect(runtime.contains("image.loading = \"lazy\""))
        #expect(runtime.contains("image.loading = \"eager\""))
    }

    @Test
    func payloadEscapesMarkupBeforeItEntersTheHTMLDocument() throws {
        let html = try MarkdownHTMLShell.make(
            content: "<script>alert('xss')</script>\n[bad](javascript:alert(1))",
            baseURL: nil,
            configuration: .default
        )

        #expect(!html.contains("<script>alert('xss')</script>"))
        let runtime = String(data: MarkdownResourceCatalog.data(for: .runtime) ?? Data(), encoding: .utf8) ?? ""
        #expect(runtime.contains("DOMPurify.sanitize"))
        #expect(runtime.contains("FORBID_TAGS"))
        #expect(html.contains("default-src 'none'"))
        #expect(html.contains("img-src leonardo-document: data: http: https:"))
        #expect(!html.contains("img-src leonardo-document: file:"))
    }

    @Test
    func unsafeAppearanceValuesAreRejectedBeforeCSSInjection() throws {
        var appearance = MarkdownAppearance.default
        appearance.backgroundHex = "#fff; background: url(https://evil.test)"
        let configuration = MarkdownPreviewConfiguration(appearance: appearance)
        let html = try MarkdownHTMLShell.make(content: "# title", baseURL: nil, configuration: configuration)

        #expect(html.contains("\"background\":\"#000000\""))
        #expect(!html.contains("evil.test"))
    }

    @Test
    func linksResolveRelativeFilesAndRejectExecutableSchemes() {
        let document = URL(fileURLWithPath: "/tmp/docs/readme.md")
        let directory = URL(fileURLWithPath: "/tmp/docs")
        let image = MarkdownURLResolver.resolve("images/diagram.png", relativeTo: document)
        let directoryImage = MarkdownURLResolver.resolve("images/diagram.png", relativeTo: directory)
        let fragment = MarkdownURLResolver.resolve("#section", relativeTo: directory)
        let external = MarkdownURLResolver.resolve("https://example.com/docs", relativeTo: document)
        let script = MarkdownURLResolver.resolve("javascript:alert(1)", relativeTo: document)
        let data = MarkdownURLResolver.resolve("data:text/html,unsafe", relativeTo: document)

        #expect(image?.path == "/tmp/docs/images/diagram.png")
        #expect(directoryImage?.path == "/tmp/docs/images/diagram.png")
        let explicitDirectory = URL(fileURLWithPath: "/tmp/docs/", isDirectory: true)
        let spacedDirectory = URL(fileURLWithPath: "/tmp/my docs")
        #expect(MarkdownURLResolver.resolve("images/diagram.png", relativeTo: explicitDirectory)?.path == "/tmp/docs/images/diagram.png")
        #expect(MarkdownURLResolver.resolve("images/diagrama ñ.png", relativeTo: spacedDirectory)?.path == "/tmp/my docs/images/diagrama ñ.png")
        #expect(fragment?.path == "/tmp/docs")
        #expect(external?.scheme == "https")
        #expect(script == nil)
        #expect(data == nil)
    }

    @Test
    func filePreviewsUseTheConstrainedDocumentScheme() throws {
        let directory = URL(fileURLWithPath: "/tmp/Examples/Proyecto/docs")
        let request = URL(string: "leonardo-document://local/../recursos/marca.svg")
        let resolved = request.flatMap {
            MarkdownDocumentSchemeHandler.resolvedFileURL(
                baseDirectory: directory,
                assetRoot: directory.deletingLastPathComponent(),
                requestURL: $0
            )
        }
        let html = try MarkdownHTMLShell.make(
            content: "![diagram](../recursos/diagrama.svg)",
            baseURL: directory,
            configuration: .default
        )

        #expect(html.contains("<base href=\"leonardo-document://local/docs/\">"))
        #expect(html.contains("img-src leonardo-document:"))
        #expect(resolved?.path == "/tmp/Examples/Proyecto/recursos/marca.svg")
    }

    @Test
    func frontMatterIsRemovedFromBodyAndRetainedAsMetadata() {
        let document = MarkdownDocumentParser.parse("---\ntitle: 'A note'\ntags: docs\n---\n# Body")

        #expect(document.frontMatter["title"] == "A note")
        #expect(document.frontMatter["tags"] == "docs")
        #expect(document.body == "# Body")
    }

    @Test
    func bundledSourceMetadataIncludesPinnedHashesAndLicenseFiles() throws {
        let metadata = try #require(MarkdownResourceCatalog.url(forFile: "THIRD_PARTY_SOURCES.json"))
        let data = try Data(contentsOf: metadata)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("marked"))
        #expect(json.contains("15.0.7"))
        #expect(json.contains("ae501969d4c7f1b433d80db12aea7e4228291e18fa8121e46337c73cb09c8683"))
        #expect(json.contains("3.4.16"))
        #expect(json.contains("2c90a9b46d6463f26038a29b686e82bc91de01fdac9d5229e7cfe3b360134ea2"))
        #expect(json.contains("11.16.1"))
        #expect(json.contains("8ffa273dc08103c033f013a6308a59eb93d452804f3c2656fda0f6619168482c"))
        #expect(json.contains("0.18.2"))
        #expect(json.contains("90354db602936d813daadda391a4376d071f5d1241d8cfddf091df4c2e38730d"))
        #expect(MarkdownResourceCatalog.url(forFile: "marked-15.0.7.txt") != nil)
        #expect(MarkdownResourceCatalog.url(forFile: "dompurify-3.4.16.txt") != nil)
        #expect(MarkdownResourceCatalog.url(forFile: "highlight.js-11.12.0.txt") != nil)
        #expect(MarkdownResourceCatalog.url(forFile: "mermaid-11.16.1.txt") != nil)
        #expect(MarkdownResourceCatalog.url(forFile: "katex-0.18.2.txt") != nil)
    }
}
