import Foundation
import Testing
@testable import LeonardoCore

struct LeonardoPackageTests {
    private func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func source(_ body: String = "# Document") throws -> String {
        try LeonardoFormatParser.serialize(LeonardoDocument(body: body))
    }

    @Test func packageRoundTripPreservesAssetsAndRefreshesConflictFingerprint() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("form.mdlr")
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("logo.png"))
        let text = try source("# Form\n![logo](logo.png)")
        try text.write(to: original, atomically: true, encoding: .utf8)
        let package = root.appendingPathComponent("form.mdlz")
        try LeonardoPackageTransport.export(documentURL: original, content: text, to: package)
        var workspace = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(workspace) }
        #expect(workspace.documentURL.pathExtension == "mdlr")
        let exported = try String(contentsOf: workspace.documentURL, encoding: .utf8)
        #expect(exported.contains("assets/"))
        #expect(try String(contentsOf: original, encoding: .utf8) == text)
        try (exported + "\nChanged").write(to: workspace.documentURL, atomically: true, encoding: .utf8)
        workspace = try LeonardoPackageTransport.save(workspace)
        workspace = try LeonardoPackageTransport.save(workspace)
        let reopened = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(reopened) }
        #expect(try String(contentsOf: reopened.documentURL, encoding: .utf8).hasSuffix("Changed"))
        let images = try FileManager.default.contentsOfDirectory(at: reopened.directoryURL.appendingPathComponent("assets"), includingPropertiesForKeys: nil)
        #expect(images.count == 1)
        #expect(try Data(contentsOf: images[0]) == Data([1, 2, 3]))
    }

    @Test func balancedAndEscapedImagePathsUseTheSharedPortableScanner() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("form.mdlf")
        let asset = root.appendingPathComponent("a_(b).png")
        try Data([1, 2, 3]).write(to: asset)
        for (index, reference) in ["a_(b).png", #"a_\(b\).png"#, "<a_(b).png>"].enumerated() {
            let remote = #"![remote](https://example.com/a_\(.png)"#
            let body = "![nested [logo]](\(reference))\n" + remote
            let document = LeonardoDocument(body: body)
            #expect(try LeonardoLocalImagePolicy.hasLocalResources(in: document))
            let text = try LeonardoFormatParser.serialize(document)
            let package = root.appendingPathComponent("copy-\(index).mdlz")
            try LeonardoPackageTransport.export(documentURL: original, content: text, to: package)
            let workspace = try LeonardoPackageTransport.open(package)
            defer { LeonardoPackageTransport.discard(workspace) }
            let assets = try FileManager.default.contentsOfDirectory(at: workspace.directoryURL.appendingPathComponent("assets"), includingPropertiesForKeys: nil)
            #expect(assets.count == 1)
            #expect(try Data(contentsOf: assets[0]) == Data([1, 2, 3]))
            let exported = try String(contentsOf: workspace.documentURL, encoding: .utf8)
            #expect(exported.contains("![nested [logo]]("))
            #expect(exported.contains("assets/"))
            #expect(!exported.contains("a_(b).png"))
            #expect(exported.contains(remote))
        }
    }

    @Test func htmlImageQuotesAndEntitiesUseTheSharedPortableScanner() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([4, 5, 6]).write(to: root.appendingPathComponent("a>b.png"))
        let body = #"<img alt="caption > text" src="a&gt;b.png">"#
        let text = try source(body)
        let package = root.appendingPathComponent("html.mdlz")
        try LeonardoPackageTransport.export(documentURL: root.appendingPathComponent("html.mdlf"), content: text, to: package)
        let workspace = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(workspace) }
        let assets = try FileManager.default.contentsOfDirectory(at: workspace.directoryURL.appendingPathComponent("assets"), includingPropertiesForKeys: nil)
        #expect(assets.count == 1)
        #expect(try Data(contentsOf: assets[0]) == Data([4, 5, 6]))
        let exported = try String(contentsOf: workspace.documentURL, encoding: .utf8)
        #expect(exported.contains(#"alt="caption > text""#))
        #expect(exported.contains(#"src="assets/"#))
    }

    @Test func extractionLeavesOriginalPackageUntouchedAndNeverOverwrites() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("test.mdlf")
        let package = root.appendingPathComponent("test.mdlz")
        try LeonardoPackageTransport.export(documentURL: document, content: source(), to: package)
        let before = try Data(contentsOf: package)
        let folder = root.appendingPathComponent("extracted")
        let extracted = try LeonardoPackageTransport.open(package, extractingTo: folder)
        #expect(extracted.packageURL == nil)
        try "changed".write(to: extracted.documentURL, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.save(extracted)
        #expect(try Data(contentsOf: package) == before)
        #expect(throws: LeonardoPackageError.self) { try LeonardoPackageTransport.open(package, extractingTo: folder) }
        LeonardoPackageTransport.discard(extracted)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func renamedPackageKeepsItsWorkspaceAndSaveTarget() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("before.mdlz")
        let moved = root.appendingPathComponent("after.mdlz")
        try LeonardoPackageTransport.export(documentURL: root.appendingPathComponent("form.mdlf"), content: source(), to: package)
        var opened = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(opened) }
        try FileManager.default.moveItem(at: package, to: moved)
        opened = LeonardoPackageTransport.relocating(opened, to: moved)
        opened = try LeonardoPackageTransport.save(opened)
        #expect(opened.packageURL == moved)
        #expect(!FileManager.default.fileExists(atPath: package.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func externalPackageChangesRejectSave() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appendingPathComponent("test.mdlz")
        try LeonardoPackageTransport.export(documentURL: root.appendingPathComponent("test.mdlf"), content: source(), to: package)
        let opened = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(opened) }
        try Data("external".utf8).write(to: package)
        #expect(throws: LeonardoPackageError.self) { try LeonardoPackageTransport.save(opened) }
        #expect(try Data(contentsOf: package) == Data("external".utf8))
    }

    @Test func zipRejectsTraversalDuplicateNamesAndCorruptionBeforeExtraction() throws {
        #expect(!LeonardoZIPArchive.safePath("../outside"))
        #expect(!LeonardoZIPArchive.safePath("assets/../../outside"))
        #expect(!LeonardoZIPArchive.safePath("/absolute"))
        #expect(!LeonardoZIPArchive.safePath("assets\\outside"))
        let document = LeonardoZIPArchive.Entry(name: "document.mdlf", data: Data(try source().utf8))
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.write([document, document])
        }
        var corrupt = try LeonardoZIPArchive.write([document])
        corrupt[30 + document.name.utf8.count] ^= 1
        #expect(throws: LeonardoPackageError.self) { try LeonardoZIPArchive.read(corrupt) }
        let archive = try LeonardoZIPArchive.write([document, .init(name: "assets/a", data: Data()), .init(name: "assets/a/b", data: Data())])
        #expect(throws: LeonardoPackageError.self) { try LeonardoZIPArchive.read(archive) }
    }

    @Test func zipWriterRejectsCanonicalCollisionsAndReaderRejectsNormalizedParents() throws {
        let document = LeonardoZIPArchive.Entry(name: "document.mdlf", data: Data(try source().utf8))
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.write([
                document,
                .init(name: "assets/ß", data: Data([1])),
                .init(name: "assets/ss", data: Data([2]))
            ])
        }
        let parentConflict = try LeonardoZIPArchive.write([
            document,
            .init(name: "assets/σ", data: Data([1])),
            .init(name: "assets/ς/child", data: Data([2]))
        ])
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.read(parentConflict)
        }
    }

    @Test func zipReaderRejectsUnicodeCasefoldCollisionsAndIgnoresEmptyDirectories() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("document.mdlf")
        try source().write(to: document, atomically: true, encoding: .utf8)
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let cases = [("ß", "ss"), ("σ", "ς")]
        for (index, names) in cases.enumerated() {
            let first = assets.appendingPathComponent(names.0)
            let second = assets.appendingPathComponent(names.1)
            try Data([1]).write(to: first)
            try Data([2]).write(to: second)
            let archive = root.appendingPathComponent("collision-\(index).mdlz")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.currentDirectoryURL = root
            process.arguments = ["-q", archive.path, document.lastPathComponent, "assets/\(names.0)", "assets/\(names.1)"]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(throws: LeonardoPackageError.self) {
                try LeonardoZIPArchive.read(Data(contentsOf: archive))
            }
        }

        let emptyDirectoryArchive = root.appendingPathComponent("empty-directory.mdlz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", emptyDirectoryArchive.path, document.lastPathComponent, "assets-empty"]
        try FileManager.default.createDirectory(at: root.appendingPathComponent("assets-empty"), withIntermediateDirectories: true)
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let entries = try LeonardoZIPArchive.read(Data(contentsOf: emptyDirectoryArchive))
        #expect(entries.map(\.name) == [document.lastPathComponent])
    }

    @Test func zipReaderAndWriterUseThe32MiBExpandedEnvelope() throws {
        let document = LeonardoZIPArchive.Entry(name: "document.mdlf", data: Data(try source().utf8))
        let oversized = Data(repeating: 0x5A, count: LeonardoZIPArchive.maximumExpandedBytes + 1)
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.write([document, .init(name: "assets/large.bin", data: oversized)])
        }

        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try source().write(to: root.appendingPathComponent("document.mdlf"), atomically: true, encoding: .utf8)
        try oversized.write(to: root.appendingPathComponent("large.bin"))
        let archive = root.appendingPathComponent("large.mdlz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-0", archive.path, "document.mdlf", "large.bin"]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.read(Data(contentsOf: archive))
        }
    }

    @Test func exportSkipsCodeExamplesAndKeepsMetadataResourcesInSync() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([4, 5]).write(to: root.appendingPathComponent("a b.png"))
        var document = LeonardoDocument(body: "![image](<a b.png>)\n\n`![example](missing.png)`\n\n```md\n![sample](missing.png)\n```\n")
        document.metadata.fields = ["answer": LeonardoFieldDefinition()]
        document.metadata.values = ["answer": .string("![answer](missing.png)")]
        document.metadata.layout = LeonardoLayout(background: LeonardoBackground(image: "a b.png"), images: [LeonardoImageLayout(source: "a b.png")])
        let text = try LeonardoFormatParser.serialize(document)
        let package = root.appendingPathComponent("export.mdlz")
        try LeonardoPackageTransport.export(documentURL: root.appendingPathComponent("source.mdlf"), content: text, to: package)
        let opened = try LeonardoPackageTransport.open(package)
        defer { LeonardoPackageTransport.discard(opened) }
        let parsed = try LeonardoFormatParser.parse(String(contentsOf: opened.documentURL, encoding: .utf8))
        let image = try #require(parsed.metadata.layout?.background?.image)
        #expect(image.hasPrefix("assets/"))
        #expect(parsed.metadata.layout?.images.first?.source == image)
        #expect(parsed.metadata.values["answer"] == .string("![answer](missing.png)"))
        #expect(parsed.body.contains("![image](<" + image + ">)"))
        #expect(parsed.body.contains("`![example](missing.png)`"))
        #expect(parsed.body.contains("![sample](missing.png)"))
    }

    @Test func localImagePolicyUsesThePortableScannerWithoutReadingFiles() throws {
        var ignored = LeonardoDocument(body: """
        `![inline](missing.png)`

        ```markdown
        ![fenced](missing.png)
        ```

        ![remote](https://example.com/remote.png)
        """)
        ignored.metadata.values = ["answer": .string("![value](missing.png)")]
        #expect(try LeonardoLocalImagePolicy.hasLocalResources(in: ignored) == false)

        let referenceBody = """
        ![hero][logo]
        ![logo][]
        ![logo]
        [logo]: <missing.png>
        """
        let local = LeonardoDocument(body: referenceBody)
        #expect(try LeonardoLocalImagePolicy.hasLocalResources(in: local))

        var layoutOnly = LeonardoDocument(body: "No body image")
        layoutOnly.metadata.layout = LeonardoLayout(
            background: LeonardoBackground(image: "background.png"),
            images: [LeonardoImageLayout(source: "foreground.png")]
        )
        #expect(try LeonardoLocalImagePolicy.hasLocalResources(in: layoutOnly))
    }

    @Test func exportCollectsHTMLAndReferenceImagesAndLeavesSourceUntouched() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.mdlf")
        let packageURL = root.appendingPathComponent("export.mdlz")
        try Data([7, 8, 9]).write(to: root.appendingPathComponent("logo.png"))
        let text = try source("""
        <img alt="logo" src="logo.png">
        ![hero][logo]
        ![logo][]
        ![logo]

        [logo]: <logo.png>

        <img src="https://example.com/remote.png">
        `![ignored](missing.png)`

        ```md
        <img src="missing.png">
        ```
        """)
        try text.write(to: sourceURL, atomically: true, encoding: .utf8)

        try LeonardoPackageTransport.export(documentURL: sourceURL, content: text, to: packageURL)
        let workspace = try LeonardoPackageTransport.open(packageURL)
        defer { LeonardoPackageTransport.discard(workspace) }
        let parsed = try LeonardoFormatParser.parse(String(contentsOf: workspace.documentURL, encoding: .utf8))
        let assets = try FileManager.default.contentsOfDirectory(
            at: workspace.directoryURL.appendingPathComponent("assets"),
            includingPropertiesForKeys: nil
        )
        let asset = try #require(assets.first?.lastPathComponent)
        let assetPath = "assets/\(asset)"

        #expect(try String(contentsOf: sourceURL, encoding: .utf8) == text)
        #expect(parsed.body.contains("<img alt=\"logo\" src=\"\(assetPath)\">"))
        #expect(parsed.body.contains("![hero][logo]"))
        #expect(parsed.body.contains("![logo][]"))
        #expect(parsed.body.contains("![logo]\n\n[logo]:"))
        #expect(parsed.body.contains("[logo]: <\(assetPath)>"))
        #expect(parsed.body.contains("https://example.com/remote.png"))
        #expect(parsed.body.contains("`![ignored](missing.png)`"))
        #expect(parsed.body.contains("<img src=\"missing.png\">"))
        #expect(assets.count == 1)
    }

    @Test func exportUsesTheSameLocalImageBoundaryAsPreview() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let docs = root.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("outside.png"))
        try "private content".write(to: docs.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        let target = root.appendingPathComponent("export.mdlz")
        let documentURL = docs.appendingPathComponent("form.mdlf")
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoPackageTransport.export(documentURL: documentURL, content: source("![outside](../outside.png)"), to: target)
        }
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoPackageTransport.export(documentURL: documentURL, content: source("![secret](secret.txt)"), to: target)
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
        try LeonardoPackageTransport.export(documentURL: documentURL, content: source("![project](../outside.png)"), to: target, assetRoot: root)
        let opened = try LeonardoPackageTransport.open(target)
        defer { LeonardoPackageTransport.discard(opened) }
        #expect(FileManager.default.fileExists(atPath: opened.documentURL.path))
    }

    @Test func ordinaryDeflateZipFromSystemToolIsAccepted() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let document = root.appendingPathComponent("document.mdlf")
        try source(String(repeating: "Hello\n", count: 100)).write(to: document, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "document.mdlz", "document.mdlf"]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let workspace = try LeonardoPackageTransport.open(root.appendingPathComponent("document.mdlz"))
        defer { LeonardoPackageTransport.discard(workspace) }
        #expect(try String(contentsOf: workspace.documentURL, encoding: .utf8) == String(contentsOf: document, encoding: .utf8))
    }
}
