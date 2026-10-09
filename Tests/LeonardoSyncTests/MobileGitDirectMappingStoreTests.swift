import Foundation
import XCTest
@testable import LeonardoSync

final class MobileGitDirectMappingStoreTests: XCTestCase {
    func testRoundTripUsesPrivateFileAndDirectoryPermissions() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("GitDirectMappings.json")
        let store = MobileGitDirectMappingStore(url: url)
        let mapping = MobileGitDirectMapping(
            gitProjectID: UUID(), connectionID: UUID(), sourceProjectID: UUID())

        try await store.save([mapping.gitProjectID: mapping])
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [mapping.gitProjectID: mapping])

        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
        let filePermissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(filePermissions?.intValue, 0o600)
    }

    func testTrustedParentAliasIsResolvedButFinalEntryRemainsWritable() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let realParent = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: true)
        let aliasParent = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasParent, withDestinationURL: realParent)
        let url = aliasParent.appendingPathComponent("GitDirectMappings.json")
        let store = MobileGitDirectMappingStore(url: url)
        let mapping = MobileGitDirectMapping(gitProjectID: UUID(), connectionID: UUID(), sourceProjectID: UUID())

        try await store.save([mapping.gitProjectID: mapping])
        XCTAssertTrue(FileManager.default.fileExists(atPath: realParent.appendingPathComponent("GitDirectMappings.json").path))
        let loaded = try await store.load()
        XCTAssertEqual(loaded[mapping.gitProjectID], mapping)
    }

    func testFinalSymlinkIsRejectedWithoutChangingOutsideTarget() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("mapping-outside-(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: outside) }
        let sentinel = Data("outside remains unchanged\n".utf8)
        try sentinel.write(to: outside, options: .atomic)
        let url = root.appendingPathComponent("GitDirectMappings.json")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: outside)
        let store = MobileGitDirectMappingStore(url: url)
        let mapping = MobileGitDirectMapping(gitProjectID: UUID(), connectionID: UUID(), sourceProjectID: UUID())

        do {
            try await store.save([mapping.gitProjectID: mapping])
            XCTFail("A symlinked final mapping entry must be rejected")
        } catch let error as SyncError {
            XCTAssertEqual(error, .invalidPath)
        }
        XCTAssertEqual(try Data(contentsOf: outside), sentinel)
    }

    func testDuplicateGitProjectIDsAreRejectedOnLoad() async throws {
        let root = try makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("GitDirectMappings.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let projectID = UUID()
        let first = MobileGitDirectMapping(gitProjectID: projectID, connectionID: UUID(), sourceProjectID: UUID())
        let second = MobileGitDirectMapping(gitProjectID: projectID, connectionID: UUID(), sourceProjectID: UUID())
        try JSONEncoder().encode([first, second]).write(to: url, options: .atomic)
        let store = MobileGitDirectMappingStore(url: url)

        do {
            _ = try await store.load()
            XCTFail("Duplicate project mappings must be rejected")
        } catch let error as SyncError {
            XCTAssertEqual(error, .invalidSnapshot)
        }
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("little-leonardo-mapping-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return root
    }
}
