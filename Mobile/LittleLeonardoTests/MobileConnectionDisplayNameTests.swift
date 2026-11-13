import XCTest
import LeonardoSync
@testable import LittleLeonardo

@MainActor
final class MobileConnectionDisplayNameTests: XCTestCase {
    private let connectionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let deviceID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let projectID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    private func connection(endpoint: String = "https://10.0.8.158:40882") -> MobileDirectConnection {
        MobileDirectConnection(connectionID: connectionID, deviceID: deviceID,
            endpoint: URL(string: endpoint)!, fingerprint: Data(repeating: 7, count: 32),
            projectIDs: [projectID], comparisonCode: "123456",
            capabilities: [.rubricExchangeV1], acceptedProjectIDs: [projectID])
    }

    func testRenamePersistsWithoutChangingConnectionIdentityOrGrants() throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let value = connection()
        let library = MobileLibrary(rootURL: support.appendingPathComponent("Corpus", isDirectory: true))
        library.connections = [value]

        XCTAssertTrue(library.renameConnection(connectionID: value.connectionID,
                                               displayName: "  MacBook Pro de Javier  "))
        XCTAssertFalse(library.connections[0].showsEndpointAddressInHostRow)
        var staleOperationSnapshot = value
        staleOperationSnapshot.capabilityRefreshAttempted = true
        XCTAssertNotNil(library.commitConnection(staleOperationSnapshot,
                                                 expected: library.token(for: staleOperationSnapshot)))
        XCTAssertEqual(library.connections[0].displayName, "MacBook Pro de Javier")

        let store = MobileDirectConnectionStore(url: support.appendingPathComponent("connections.json"))
        let saved = try XCTUnwrap(store.load().first)
        XCTAssertEqual(saved.displayName, "MacBook Pro de Javier")
        XCTAssertEqual(saved.connectionID, value.connectionID)
        XCTAssertEqual(saved.deviceID, value.deviceID)
        XCTAssertEqual(saved.endpoint, value.endpoint)
        XCTAssertEqual(saved.fingerprint, value.fingerprint)
        XCTAssertEqual(saved.projectIDs, value.projectIDs)
        XCTAssertEqual(saved.acceptedProjectIDs, value.acceptedProjectIDs)
        XCTAssertEqual(saved.ignoredProjectIDs, value.ignoredProjectIDs)
        XCTAssertEqual(saved.capabilities, value.capabilities)
    }

    func testIPUsesFriendlyFallbackAndOldConnectionDataStillDecodes() throws {
        let value = connection()
        XCTAssertEqual(value.suggestedDisplayName, "Mac conectado")
        XCTAssertTrue(value.showsEndpointAddressInHostRow)
        XCTAssertEqual(value.endpointAddress, "10.0.8.158:40882")
        XCTAssertEqual(connection(endpoint: "https://[fe80::1]:40882").endpointAddress,
                         "[fe80::1]:40882")

        let encoded = try JSONEncoder().encode(value)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        fields.removeValue(forKey: "displayName")
        let legacyData = try JSONSerialization.data(withJSONObject: fields)
        let decoded = try JSONDecoder().decode(MobileDirectConnection.self, from: legacyData)
        XCTAssertNil(decoded.displayName)
        XCTAssertEqual(decoded.visibleDisplayName, "Mac conectado")
        XCTAssertTrue(decoded.showsEndpointAddressInHostRow)
    }

    func testLocalHostnameIsSuggestedWhenAvailable() {
        let value = connection(endpoint: "https://MacBook-Pro-de-Javier.local:40882")
        XCTAssertEqual(value.suggestedDisplayName.lowercased(), "macbook pro de javier")
        XCTAssertFalse(value.showsEndpointAddressInHostRow)
    }
}
