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
