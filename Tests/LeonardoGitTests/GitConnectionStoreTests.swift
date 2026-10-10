import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitConnectionStoreTests: XCTestCase {
    func testConnectionRoundTripsScopeWithoutSecretsAndRemoves() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GitConnectionStore(root: root)
        let id = UUID()
        let connection = try GitProjectConnection(projectID: id, endpoint: URL(string: "https://fixture.invalid/project.git")!,
                                                 branch: "refs/heads/main", scope: CorpusScope(folder: "docs"), username: "fixture")
        try await store.save(connection)
        let reloaded = try await store.load(id: id)
        XCTAssertEqual(reloaded, connection)
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        let json = try XCTUnwrap(String(data: Data(contentsOf: url), encoding: .utf8))
        XCTAssertFalse(json.contains("password"))
        XCTAssertFalse(json.contains("token"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try await store.remove(id: id)
        let absent = try await store.load(id: id)
        XCTAssertNil(absent)
    }

    func testUntrustedPersistedEndpointIdentityAndSymlinkFail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = GitConnectionStore(root: root)
        let id = UUID()
        let connection = try GitProjectConnection(projectID: id, endpoint: URL(string: "https://fixture.invalid/project.git")!,
                                                 branch: "refs/heads/main", scope: CorpusScope(folder: "docs"))
        let data = try JSONEncoder().encode(connection)
        let url = root.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        try Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "https:", with: "http:").utf8).write(to: url)
        do { _ = try await store.load(id: id); XCTFail("Unencrypted endpoint accepted") } catch {}
        let wrongID = root.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try data.write(to: wrongID)
        do { _ = try await store.load(id: UUID(uuidString: wrongID.deletingPathExtension().lastPathComponent)!); XCTFail("Wrong identity accepted") } catch {}
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: wrongID)
        do { try await store.save(connection); XCTFail("Symlink write accepted") } catch {}
        do { _ = try await store.load(id: id); XCTFail("Symlink read accepted") } catch {}
    }

    func testInvalidBranchUsernameAndCredentialValuesFailBeforeStorage() async throws {
        let reservedPublication = "refs/heads/little-leonardo/main"
        let reservedIntegration = "refs/heads/little-leonardo-integrations/device/project/proposal"
        for branch in ["main", "refs/tags/release", "refs/heads/a..b", reservedPublication, reservedIntegration,
                       "refs/heads/little-leonardo", "refs/heads/little-leonardo-integrations"] {
            XCTAssertThrowsError(try GitProjectConnection(projectID: UUID(), endpoint: URL(string: "https://fixture.invalid/repo")!,
                                                         branch: branch, scope: CorpusScope(folder: "docs")))
        }
        XCTAssertNoThrow(try GitProjectConnection(projectID: UUID(), endpoint: URL(string: "https://fixture.invalid/repo")!,
                                                  branch: "refs/heads/little-leonardo-notes", scope: CorpusScope(folder: "docs")))
        let store = GitCredentialStore(service: "fixture.invalid.unused")
        for value in ["", "line\nsecret", String(repeating: "a", count: 16 * 1_024 + 1)] {
            do { try await store.save(value, projectID: UUID()); XCTFail("Invalid secret accepted") } catch {}
        }
        let direct = SecureCredentialStore(service: "fixture.invalid.unused.direct")
        do { try await direct.save("not-a-pairing-credential", deviceID: UUID()); XCTFail("Invalid direct credential accepted") } catch {}
    }
}
