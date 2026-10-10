import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitWireTests: XCTestCase {
    func testBinaryPacketsAndControlMarkersRoundTrip() throws {
        let packets: [GitPacket] = [.data(Data([0, 255, 10, 13])), .delimiter, .data(Data()), .flush, .responseEnd]
        let encoded = try packets.reduce(into: Data()) { $0 += try $1.encoded() }
        XCTAssertEqual(try GitPacket.decode(encoded), packets)
        for invalid in ["0003", "ffff", "000", "0007a", "zzzz"] {
            XCTAssertThrowsError(try GitPacket.decode(Data(invalid.utf8)))
        }
        XCTAssertThrowsError(try GitPacket.decode(encoded, maximumBytes: 3))
        XCTAssertThrowsError(try GitPacket.decode(encoded, maximumPackets: 1))
        XCTAssertThrowsError(try GitPacket.data(Data(repeating: 0, count: 65_517)).encoded())
    }

    func testMissingFilteringAndMalformedCapabilitiesCannotProduceFetch() throws {
        for lines in [["version 2", "ls-refs", "fetch=shallow"],
                      ["version 2", "ls-refs", "fetch=filter"],
                      ["version 2", "ls-refs", "fetch=shallow filter", "fetch=shallow filter"],
                      ["version 2", ""], ["version 1", "fetch=shallow filter"]] {
            let advertisement = try advertise(lines)
            XCTAssertThrowsError(try GitV2Capabilities(advertisement: advertisement).metadataRequest(want: String(repeating: "a", count: 40)))
        }
        let supported = try GitV2Capabilities(advertisement: advertise(["version 2", "ls-refs", "fetch=shallow filter"]))
        XCTAssertThrowsError(try supported.metadataRequest(want: "a\nfilter blob:limit=999"))
        let packets = try GitPacket.decode(supported.metadataRequest(want: String(repeating: "a", count: 40)))
        XCTAssertTrue(packets.contains(.data(Data("filter blob:none\n".utf8))))
        XCTAssertTrue(packets.contains(.data(Data("deepen 1\n".utf8))))
    }

    func testSmartHTTPServiceEnvelopeRequiresExactServiceAndFlush() throws {
        let capabilities = try advertise(["version 2", "ls-refs", "fetch=shallow filter"])
        let envelope = try GitPacket.data(Data("# service=git-upload-pack\n".utf8)).encoded() + GitPacket.flush.encoded()
        try GitV2Capabilities(advertisement: envelope + capabilities).requireFolderTransfer()
        for prefix in [
            try GitPacket.data(Data("# service=git-receive-pack\n".utf8)).encoded() + GitPacket.flush.encoded(),
            try GitPacket.data(Data("# service=git-upload-pack\n".utf8)).encoded() + GitPacket.delimiter.encoded(),
            try GitPacket.data(Data("# service=git-upload-pack\n".utf8)).encoded()
        ] { XCTAssertThrowsError(try GitV2Capabilities(advertisement: prefix + capabilities)) }
        XCTAssertThrowsError(try GitV2Capabilities(advertisement: envelope + envelope + capabilities))
    }

    #if os(macOS)
    func testRealGitReferenceDiscoveryForSHA1SHA256AndUnbornHEAD() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for format in ["sha1", "sha256"] {
            let source = root.appendingPathComponent(format)
            _ = try git(["init", "--quiet", "--initial-branch=main", "--object-format=\(format)", source.path])
            _ = try git(["-C", source.path, "config", "uploadpack.allowFilter", "true"])
            let capability = try GitV2Capabilities(advertisement: git(["upload-pack", "--stateless-rpc", "--advertise-refs", source.path]))
            let unborn = try capability.references(response: git(["upload-pack", "--stateless-rpc", source.path], input: capability.referenceRequest()))
            XCTAssertEqual(unborn.count, 1)
            XCTAssertEqual(unborn.first?.name, "HEAD")
            XCTAssertNil(unborn.first?.objectID)
            XCTAssertEqual(unborn.first?.symbolicTarget, "refs/heads/main")
            _ = try git(["-C", source.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--allow-empty", "--quiet", "-m", "fixture"])
            _ = try git(["-C", source.path, "branch", "notes/ñ"])
            let refs = try capability.references(response: git(["upload-pack", "--stateless-rpc", source.path], input: capability.referenceRequest()))
            XCTAssertEqual(refs.map(\.name), ["HEAD", "refs/heads/main", "refs/heads/notes/ñ"])
            XCTAssertEqual(refs.first?.objectID?.count, format == "sha1" ? 40 : 64)
            let tip = try XCTUnwrap(refs.first?.objectID)
            let fetched = try GitFetchResponse(response: git(["upload-pack", "--stateless-rpc", source.path], input: capability.metadataRequest(want: tip)), capabilities: capability)
            XCTAssertEqual(fetched.objectCount, 2)
            let decoded = try GitPack.decode(fetched, sha256: format == "sha256")
            XCTAssertEqual(Set(decoded.map(\.kind)), [.commit, .tree])
            XCTAssertTrue(decoded.contains { $0.id == tip })
        }
    }

    func testScopedCommitsAndWrittenPacksAreAcceptedByRealGit() async throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: container) }
        for format in ["sha1", "sha256"] {
            let root = container.appendingPathComponent(format)
            _ = try git(["init", "--quiet", "--object-format=\(format)", root.path])
            try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
            for (path, content) in [("docs/edit.md", "old"), ("docs/delete.md", "delete"), ("docs/code.swift", "untouched code"), ("docs/new.md", "unchanged sibling"), ("outside.bin", "outside bytes")] {
                try Data(content.utf8).write(to: root.appendingPathComponent(path))
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("docs/edit.md").path)
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs/link.md"), withDestinationURL: root.appendingPathComponent("outside.bin"))
            _ = try git(["-C", root.path, "add", "."])
            _ = try git(["-C", root.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture"])
            _ = try git(["-C", root.path, "config", "uploadpack.allowFilter", "true"])
            _ = try git(["-C", root.path, "config", "uploadpack.allowReachableSHA1InWant", "true"])
            let gitlink = String(decoding: try git(["-C", root.path, "rev-parse", "HEAD"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try git(["-C", root.path, "update-index", "--add", "--cacheinfo", "160000,\(gitlink),docs/submodule"])
            _ = try git(["-C", root.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "submodule fixture"])
            let reader = GitRemoteReader(transport: GitUploadFixture(root: root.path))
            let discovery = try await reader.discover()
            let tip = try XCTUnwrap(discovery.references.first(where: { $0.name == "HEAD" })?.objectID)
            let metadata = try await reader.metadata(commitID: tip, discovery: discovery)
            let scope = try CorpusScope(folder: "docs")
            let snapshot = try await reader.snapshot(metadata: metadata, scope: scope)
            var project = try OfflineProject(name: "Fixture", mode: .git, scope: scope, snapshot: snapshot)
            try project.write(path: "docs/edit.md", content: Data("edited".utf8))
            try project.delete(path: "docs/delete.md")
            try project.write(path: "docs/new/deep.md", content: Data("created".utf8))
            try project.write(path: "docs/empty.md", content: Data())
            let identity = try GitCommitIdentity(name: "Mobile Fixture", email: "fixture@example.invalid", timestamp: 1_700_000_000)
            let built = try GitCommitBuilder.build(project: project, baseline: metadata.baseline, identity: identity)
            XCTAssertEqual(built.objects.filter { $0.kind == .blob }.count, 3)
            let pack = try GitPackWriter.encode(objects: built.objects, sha256: format == "sha256")
            _ = try git(["-C", root.path, "index-pack", "--stdin"], input: pack)
            XCTAssertEqual(try git(["-C", root.path, "cat-file", "commit", built.commit.id]), built.commit.data)
            let changed = String(decoding: try git(["-C", root.path, "diff-tree", "--no-commit-id", "--name-only", "-r", tip, built.commit.id]), as: UTF8.self)
            XCTAssertEqual(Set(changed.split(separator: "\n")), ["docs/edit.md", "docs/delete.md", "docs/new/deep.md", "docs/empty.md"])
            for path in ["outside.bin", "docs/code.swift", "docs/link.md", "docs/submodule", "docs/new.md"] {
                let before = try git(["-C", root.path, "ls-tree", tip, "--", path])
                XCTAssertEqual(before, try git(["-C", root.path, "ls-tree", built.commit.id, "--", path]), path)
            }
            let editedMode = String(decoding: try git(["-C", root.path, "ls-tree", built.commit.id, "--", "docs/edit.md"]), as: UTF8.self)
            XCTAssertTrue(editedMode.hasPrefix("100755"))
            XCTAssertEqual(try git(["-C", root.path, "show", "\(built.commit.id):docs/new/deep.md"]), Data("created".utf8))
            _ = try git(["-C", root.path, "fsck", "--full"])
            XCTAssertThrowsError(try GitPackWriter.encode(objects: built.objects, sha256: format == "sha256", maximumBytes: 20))
            XCTAssertThrowsError(try GitCommitIdentity(name: "Injected\ncommitter", email: "x", timestamp: 0))
        }
    }

    func testRealGitPackObjectsIncludingDeltasMatchCanonicalObjects() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try git(["init", "--quiet", root.path])
        let repeated = String(repeating: "Shared document paragraph with stable content.\n", count: 400)
        for index in 0..<12 {
            try Data((repeated + "Revision \(index)\n").utf8).write(to: root.appendingPathComponent("note.md"))
            _ = try git(["-C", root.path, "add", "."])
            _ = try git(["-C", root.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "revision"])
        }
        let caps = try GitV2Capabilities(advertisement: advertise(["version 2", "ls-refs", "fetch=shallow filter"]))
        for options in [[], ["--delta-base-offset"]] {
            let pack = try git(["-C", root.path, "pack-objects", "--all", "--stdout"] + options)
            var wire = try GitPacket.data(Data("packfile\n".utf8)).encoded()
            for start in stride(from: 0, to: pack.count, by: 60_000) {
                wire += try GitPacket.data(Data([1]) + pack[start..<min(start + 60_000, pack.count)]).encoded()
            }
            wire += try GitPacket.flush.encoded()
            let response = try GitFetchResponse(response: wire, capabilities: caps)
            let objects = try GitPack.decode(response)
            XCTAssertEqual(objects.count, 36)
            for object in objects {
                XCTAssertEqual(object.data, try git(["-C", root.path, "cat-file", object.kind.rawValue, object.id]))
            }
            var limits = GitPack.Limits()
            limits.deltaDepth = 0
            XCTAssertThrowsError(try GitPack.decode(response, limits: limits), "Fixture must contain actual deltas")
            limits = GitPack.Limits(); limits.totalBytes = 1
            XCTAssertThrowsError(try GitPack.decode(response, limits: limits))
        }
    }

    func testReferenceValidationMatchesGitAndRejectsDuplicateOrInjectedReplies() throws {
        let names = ["refs/heads/main", "refs/heads/notes/ñ", "refs/heads/.hidden", "refs/heads/a..b",
                     "refs/heads/a.lock", "refs/heads/a//b", "refs/heads/a@{b", "refs/heads/a b", "refs/heads/a."]
        for name in names {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["check-ref-format", name]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(GitReference.isValidName(name), process.terminationStatus == 0, name)
        }
        let capability = try GitV2Capabilities(advertisement: advertise(["version 2", "ls-refs=unborn", "fetch=shallow filter"]))
        let oid = String(repeating: "a", count: 40)
        func reply(_ lines: [String]) throws -> Data { try advertise(lines) }
        XCTAssertThrowsError(try capability.references(response: reply(["\(oid) refs/heads/main", "\(oid) refs/heads/main"])))
        XCTAssertThrowsError(try capability.references(response: reply(["\(oid) refs/heads/main\nwant private"])))
        XCTAssertThrowsError(try capability.references(response: reply(["unborn HEAD"])))
        let filtered = try capability.references(response: reply(["\(oid) refs/tags/release", "\(oid) refs/heads/main"]))
        XCTAssertEqual(filtered.map(\.name), ["refs/heads/main"])
    }

    func testMetadataFetchFromRealRepositoryContainsNoFileBlobs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source")
        _ = try git(["init", "--quiet", source.path])
        try FileManager.default.createDirectory(at: source.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data("# Selected folder".utf8).write(to: source.appendingPathComponent("docs/note.md"))
        try Data(repeating: 42, count: 16 * 1_024 * 1_024).write(to: source.appendingPathComponent("large-code.bin"))
        _ = try git(["-C", source.path, "add", "."])
        _ = try git(["-C", source.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture"])
        _ = try git(["-C", source.path, "config", "uploadpack.allowFilter", "true"])
        let tip = String(decoding: try git(["-C", source.path, "rev-parse", "HEAD"]), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let capabilities = try GitV2Capabilities(advertisement: git(["upload-pack", "--stateless-rpc", "--advertise-refs", source.path]))
        let response = try git(["upload-pack", "--stateless-rpc", source.path], input: capabilities.metadataRequest(want: tip))
        let parsed = try GitFetchResponse(response: response, capabilities: capabilities)
        let pack = parsed.pack
        let index = try GitFolderIndex(objects: GitPack.decode(parsed), commitID: tip)
        XCTAssertEqual(try index.folders(), ["docs"])
        let selected = try index.files(in: CorpusScope(folder: "docs"))
        XCTAssertEqual(selected.map(\.path), ["docs/note.md"])
        _ = try git(["-C", source.path, "config", "uploadpack.allowReachableSHA1InWant", "true"])
        let blobResponse = try git(["upload-pack", "--stateless-rpc", source.path],
                                   input: capabilities.selectedBlobRequest(objectIDs: selected.map(\.objectID)))
        let blobs = try GitPack.decode(GitFetchResponse(response: blobResponse, capabilities: capabilities))
        XCTAssertEqual(blobs.count, 1)
        XCTAssertEqual(blobs.first?.kind, .blob)
        let snapshot = try GitSelectedCorpus.snapshot(revision: tip, files: selected, blobs: blobs, scope: CorpusScope(folder: "docs"))
        XCTAssertEqual(snapshot.files, [CorpusFile(path: "docs/note.md", content: Data("# Selected folder".utf8))])
        XCTAssertThrowsError(try GitSelectedCorpus.snapshot(revision: tip, files: selected, blobs: [], scope: CorpusScope(folder: "docs")))
        XCTAssertThrowsError(try capabilities.selectedBlobRequest(objectIDs: []))
        XCTAssertThrowsError(try capabilities.selectedBlobRequest(objectIDs: [selected[0].objectID, selected[0].objectID]))

        XCTAssertThrowsError(try index.files(in: CorpusScope(folder: "missing")))
        XCTAssertEqual(parsed.objectCount, 3)
        XCTAssertTrue(parsed.shallowCommits.isSubset(of: [tip]))
        let receiver = root.appendingPathComponent("receiver")
        _ = try git(["init", "--bare", "--quiet", receiver.path])
        _ = try git(["-C", receiver.path, "index-pack", "--stdin"], input: pack)
        let types = String(decoding: try git(["-C", receiver.path, "cat-file", "--batch-all-objects", "--batch-check=%(objecttype)"]), as: UTF8.self)
        let objects = Set(types.split(separator: "\n"))
        XCTAssertEqual(objects, ["commit", "tree"], "Folder discovery must transfer no document or code blobs")
    }

    func testRemoteReaderTransfersNoContentsBeforeExplicitFolderSelection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try git(["init", "--quiet", root.path])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data("# Mobile".utf8).write(to: root.appendingPathComponent("docs/mobile.md"))
        try Data(repeating: 7, count: 16 * 1_024 * 1_024).write(to: root.appendingPathComponent("unselected.bin"))
        _ = try git(["-C", root.path, "add", "."])
        _ = try git(["-C", root.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "fixture"])
        _ = try git(["-C", root.path, "config", "uploadpack.allowFilter", "true"])
        _ = try git(["-C", root.path, "config", "uploadpack.allowReachableSHA1InWant", "true"])
        let transport = GitUploadFixture(root: root.path)
        let reader = GitRemoteReader(transport: transport)
        let discovery = try await reader.discover()
        let tip = try XCTUnwrap(discovery.references.first(where: { $0.name == "HEAD" })?.objectID)
        let metadata = try await reader.metadata(commitID: tip, discovery: discovery)
        XCTAssertFalse(metadata.objects.contains { $0.kind == .blob })
        XCTAssertEqual(try metadata.index.folders(), ["docs"])
        let beforeSelection = await transport.requests
        XCTAssertEqual(beforeSelection.count, 2)
        let snapshot = try await reader.snapshot(metadata: metadata, scope: CorpusScope(folder: "docs"))
        XCTAssertEqual(snapshot.files, [CorpusFile(path: "docs/mobile.md", content: Data("# Mobile".utf8))])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)
        let last = try GitPacket.decode(XCTUnwrap(requests.last))
        XCTAssertEqual(last.filter { if case .data(let data) = $0 { return data.starts(with: Data("want ".utf8)) }; return false }.count, 1)
        let connection = try GitProjectConnection(projectID: UUID(), endpoint: URL(string: "https://fixture.invalid/project.git")!,
            branch: try XCTUnwrap(discovery.references.first(where: { $0.name == "HEAD" })?.symbolicTarget), scope: CorpusScope(folder: "docs"))
        let original = try OfflineProject(id: connection.projectID, name: "Fixture", mode: .git, scope: connection.scope, snapshot: snapshot)
        let refresher = GitProjectRefresher(transport: transport)
        let unchanged = try await refresher.refresh(original, connection: connection)
        XCTAssertEqual(unchanged, .unchanged)
        var dirty = original
        try dirty.write(path: "docs/mobile.md", content: Data("# Local edit".utf8))
        let local = try await refresher.refresh(dirty, connection: connection)
        XCTAssertEqual(local, .localChanges)
        try Data("# Desktop edit".utf8).write(to: root.appendingPathComponent("docs/mobile.md"))
        _ = try git(["-C", root.path, "add", "."])
        _ = try git(["-C", root.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "desktop edit"])
        let conflict = try await refresher.refresh(dirty, connection: connection)
        XCTAssertEqual(conflict, .requiresReconciliation)
        XCTAssertEqual(dirty.files[0].content, Data("# Local edit".utf8))
        let clean = try await refresher.refresh(original, connection: connection)
        guard case .updated(let updated, let baseline) = clean else { return XCTFail("Clean copy did not refresh") }
        XCTAssertEqual(updated.files[0].content, Data("# Desktop edit".utf8))
        XCTAssertNotEqual(updated.base.revision, original.base.revision)
        XCTAssertEqual(baseline.commitID, updated.base.revision)
        try dirty.markPublished(revision: String(repeating: "a", count: 40))
        let pending = try await refresher.refresh(dirty, connection: connection)
        XCTAssertEqual(pending, .awaitingIntegration)

    }

    func testActualGitAdvertisementGatesPartialTransfer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try git(["init", "--bare", "--quiet", root.path])
        let disabled = try GitV2Capabilities(advertisement: git(["upload-pack", "--stateless-rpc", "--advertise-refs", root.path]))
        XCTAssertThrowsError(try disabled.requireFolderTransfer())
        _ = try git(["-C", root.path, "config", "uploadpack.allowFilter", "true"])
        let enabled = try GitV2Capabilities(advertisement: git(["upload-pack", "--stateless-rpc", "--advertise-refs", root.path]))
        try enabled.requireFolderTransfer()
        XCTAssertTrue(try enabled.metadataRequest(want: String(repeating: "a", count: 40)).contains(Data("filter blob:none\n".utf8)))
    }

    private func git(_ arguments: [String], input: Data? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["GIT_PROTOCOL": "version=2", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]) { _, new in new }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        try process.run()
        if let input {
            try stdin.fileHandleForWriting.write(contentsOf: input)
            try stdin.fileHandleForWriting.close()
        }
        let result = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return result
    }
    #endif

    private func advertise(_ lines: [String]) throws -> Data {
        var data = Data()
        for line in lines { data += try GitPacket.data(Data((line + "\n").utf8)).encoded() }
        data += try GitPacket.flush.encoded()
        return data
    }
}

#if os(macOS)
private actor GitUploadFixture: GitRemoteTransport {
    let root: String
    private(set) var requests: [Data] = []
    init(root: String) { self.root = root }
    func advertisement() async throws -> Data { try run(["--advertise-refs"]) }
    func uploadPack(request: Data) async throws -> Data {
        requests.append(request)
        return try run([], input: request)
    }
    private func run(_ options: [String], input: Data? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["upload-pack", "--stateless-rpc"] + options + [root]
        process.environment = ["GIT_PROTOCOL": "version=2", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
        let output = Pipe(), stdin = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        try process.run()
        if let input { try stdin.fileHandleForWriting.write(contentsOf: input); try stdin.fileHandleForWriting.close() }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw GitWireError.remoteFailure }
        return data
    }
}
#endif
