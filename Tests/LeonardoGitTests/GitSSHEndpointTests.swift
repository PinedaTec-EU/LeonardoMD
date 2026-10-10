import Crypto
import XCTest
@testable import LeonardoGit
import LeonardoSync

final class GitSSHEndpointTests: XCTestCase {
    func testEndpointNormalizesHostAndQuotesRepositoryPath() throws {
        let endpoint = try GitSSHEndpoint(
            url: XCTUnwrap(URL(string: "ssh://Git@Example.COM:2222/team%20repo/o%27clock.git"))
        )

        XCTAssertEqual(endpoint.host, "example.com")
        XCTAssertEqual(endpoint.port, 2_222)
        XCTAssertEqual(endpoint.username, "Git")
        XCTAssertEqual(endpoint.repositoryPath, "/team repo/o'clock.git")
        XCTAssertEqual(endpoint.pinAccount, "example.com:2222")
        XCTAssertEqual(endpoint.command(service: .uploadPack), "git-upload-pack '/team repo/o'\\''clock.git'")
        XCTAssertEqual(endpoint.command(service: .receivePack), "git-receive-pack '/team repo/o'\\''clock.git'")
    }

    func testEndpointRejectsAmbiguousOrUnsafeURLs() throws {
        let values = [
            "https://fixture.invalid/repo.git",
            "ssh://fixture.invalid/repo.git",
            "ssh://git:secret@example.com/repo.git",
            "ssh://git@example.com/repo.git?query=1",
            "ssh://git@example.com/repo.git#fragment",
            "ssh://git@example.com/a/../repo.git",
            "ssh://git@example.com/./repo.git",
            "ssh://git@example.com/",
            "ssh://git@example.com/repo%00.git"
        ]
        for value in values {
            XCTAssertThrowsError(try GitSSHEndpoint(url: XCTUnwrap(URL(string: value))), value)
        }
        XCTAssertThrowsError(try GitSSHEndpoint(url: XCTUnwrap(URL(string: "ssh://git@example.com/repo.git")), username: "other"))
    }

    func testGitProjectConnectionAcceptsTheValidatedSSHEndpoint() throws {
        let connection = try GitProjectConnection(
            projectID: UUID(),
            endpoint: XCTUnwrap(URL(string: "ssh://fixture@example.com/team/repo.git")),
            branch: "refs/heads/main",
            scope: try CorpusScope(folder: "docs"),
            username: nil
        )
        XCTAssertEqual(connection.endpoint.scheme, "ssh")
        XCTAssertNil(connection.username)
    }

    func testRawKeyMaterialAcceptsOnlyTheDeclaredAlgorithmSize() throws {
        for (algorithm, length) in [(GitSSHKeyAlgorithm.ed25519, 32),
                                    (.ecdsaP256, 32), (.ecdsaP384, 48), (.ecdsaP521, 66)] {
            let material = try GitSSHPrivateKeyMaterial(algorithm: algorithm, rawRepresentation: Data(repeating: 7, count: length))
            XCTAssertEqual(material.algorithm, algorithm)
            XCTAssertEqual(material.rawRepresentation.count, length)
        }
        for (algorithm, length) in [(GitSSHKeyAlgorithm.ed25519, 31),
                                    (.ecdsaP256, 31), (.ecdsaP384, 47), (.ecdsaP521, 65)] {
            XCTAssertThrowsError(try GitSSHPrivateKeyMaterial(algorithm: algorithm, rawRepresentation: Data(repeating: 7, count: length)))
        }
    }

    func testGeneratedKeysExposeProviderReadyOpenSSHPublicKeys() throws {
        for algorithm in GitSSHKeyAlgorithm.allCases {
            let material = try GitSSHPrivateKeyMaterial.generated(for: algorithm)
            let publicKey = try material.openSSHPublicKey()
            XCTAssertTrue(publicKey.hasPrefix(algorithm == .ed25519 ? "ssh-ed25519 " : "ecdsa-sha2-nistp"))
            XCTAssertNoThrow(try GitSSHCredential(username: "fixture", privateKey: material))
        }
    }

    func testHostKeyPinUsesOpenSSHSHA256FingerprintEncoding() throws {
        let digest = Data(SHA256.hash(data: Data("fixture host key".utf8)))
        let pin = try GitSSHHostKeyPin(host: "example.com", port: 22, algorithm: "ssh-ed25519", digest: digest)
        XCTAssertEqual(pin.fingerprint, "SHA256:" + digest.base64EncodedString().replacingOccurrences(of: "=", with: ""))
        XCTAssertThrowsError(try GitSSHHostKeyPin(host: "example.com", port: 22, algorithm: "ssh-ed25519", digest: Data(repeating: 0, count: 31)))
    }

    func testCodableDecodingRunsTheSameBoundsAsConstructors() throws {
        let decoder = JSONDecoder()
        let digest = Data(repeating: 0, count: 32).base64EncodedString()
        let invalidPin = Data("{\"host\":\"example.com\",\"port\":22,\"algorithm\":\"rsa-sha2-512\",\"digest\":\"\(digest)\"}".utf8)
        XCTAssertThrowsError(try decoder.decode(GitSSHHostKeyPin.self, from: invalidPin))

        let invalidKey = Data("{\"algorithm\":\"ed25519\",\"rawRepresentation\":\"\(Data(repeating: 0, count: 31).base64EncodedString())\"}".utf8)
        XCTAssertThrowsError(try decoder.decode(GitSSHPrivateKeyMaterial.self, from: invalidKey))

        let invalidCredential = Data("{\"username\":\"bad\\nuser\",\"privateKey\":{\"algorithm\":\"ed25519\",\"rawRepresentation\":\"\(Data(repeating: 0, count: 32).base64EncodedString())\"}}".utf8)
        XCTAssertThrowsError(try decoder.decode(GitSSHCredential.self, from: invalidCredential))

        let invalidRootEndpoint = Data(#"{"host":"example.com","port":22,"username":"git","repositoryPath":"/"}"#.utf8)
        XCTAssertThrowsError(try decoder.decode(GitSSHEndpoint.self, from: invalidRootEndpoint))
    }

    func testCredentialStoreRoundTripsOnlyTheValidatedDeviceCredential() async throws {
        let projectID = UUID()
        let store = GitSSHCredentialStore(service: "eu.pinedatec.fixture.ssh.keys.\(UUID().uuidString)")
        defer { Task { try? await store.remove(projectID: projectID) } }
        let material = try GitSSHPrivateKeyMaterial.generated(for: .ed25519)
        let credential = try GitSSHCredential(username: "fixture", privateKey: material)
        try await store.save(credential, projectID: projectID)
        let loaded = try await store.load(projectID: projectID)
        XCTAssertEqual(loaded, credential)
        try await store.remove(projectID: projectID)
        let removed = try await store.load(projectID: projectID)
        XCTAssertNil(removed)
    }
}
