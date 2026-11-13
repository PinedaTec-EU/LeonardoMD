import XCTest
import LeonardoSync
@testable import LittleLeonardo

@MainActor
final class MobileConnectionDisplayNameTests: XCTestCase {
    private let connectionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let deviceID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let projectID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

    private func connection(endpoint: String = "https://10.0.8.158:40882",
                            displayName: String? = nil) -> MobileDirectConnection {
        MobileDirectConnection(connectionID: connectionID, deviceID: deviceID,
            endpoint: URL(string: endpoint)!, fingerprint: Data(repeating: 7, count: 32),
            projectIDs: [projectID], comparisonCode: "123456",
            capabilities: [.rubricExchangeV1], acceptedProjectIDs: [projectID], displayName: displayName)
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
        XCTAssertNotNil(try library.commitConnection(staleOperationSnapshot,
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

    func testRecoveryReloadPersistsLatestAliasAcrossAsyncCacheRestoreAndRelaunch() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let corpusRoot = support.appendingPathComponent("Corpus", isDirectory: true)
        let first = connection(displayName: "Mac antiguo")
        let missingCredential = MobileDirectConnection(
            connectionID: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            deviceID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            endpoint: URL(string: "https://10.0.8.159:40882")!,
            fingerprint: Data(repeating: 8, count: 32), projectIDs: [UUID()],
            comparisonCode: nil, capabilities: [], displayName: "Otro Mac")
        let connectionStore = MobileDirectConnectionStore(url: support.appendingPathComponent("connections.json"))
        try connectionStore.save([first, missingCredential])

        let credentials = DisplayNameRecoveryCredentials(values: [first.deviceID: "credential"])
        let gate = ReloadGate()
        let cache = ReloadGateDownloadCache(
            cache: OnDemandCache(root: support.appendingPathComponent("Downloads", isDirectory: true)), gate: gate)
        let library = MobileLibrary(rootURL: corpusRoot, credentials: credentials, downloadCache: cache)
        let reload = Task { await library.reload() }

        await gate.waitUntilReached()
        XCTAssertTrue(library.connections.first(where: { $0.connectionID == missingCredential.connectionID })?.revoked == true)
        XCTAssertTrue(library.renameConnection(connectionID: first.connectionID, displayName: "Mac de Javier"))
        await gate.open()
        await reload.value

        let saved = try XCTUnwrap(connectionStore.load().first(where: { $0.connectionID == first.connectionID }))
        XCTAssertEqual(saved.displayName, "Mac de Javier")
        let repaired = try XCTUnwrap(connectionStore.load().first(where: {
            $0.connectionID == missingCredential.connectionID
        }))
        XCTAssertTrue(repaired.revoked)

        let relaunched = MobileLibrary(rootURL: corpusRoot, credentials: credentials, downloadCache: cache)
        await relaunched.reload()
        XCTAssertEqual(relaunched.connections.first(where: { $0.connectionID == first.connectionID })?.displayName,
                       "Mac de Javier")
        XCTAssertTrue(relaunched.connections.first(where: {
            $0.connectionID == missingCredential.connectionID
        })?.revoked == true)
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

private actor ReloadGate {
    private var reached = false
    private var isOpen = false
    private var entryContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        reached = true
        entryContinuation?.resume()
        entryContinuation = nil
        guard !isOpen else { return }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilReached() async {
        if reached { return }
        await withCheckedContinuation { entryContinuation = $0 }
    }

    func open() {
        isOpen = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ReloadGateDownloadCache: RemoteDownloadCache {
    private let cache: OnDemandCache
    private let gate: ReloadGate

    init(cache: OnDemandCache, gate: ReloadGate) {
        self.cache = cache
        self.gate = gate
    }

    func projects() async throws -> [CachedRemoteProject] {
        await gate.pause()
        return try await cache.projects()
    }

    func update(id: UUID, descriptor: SharedProjectDescriptor, catalogue: RemoteProjectCatalogue) async throws {
        try await cache.update(id: id, descriptor: descriptor, catalogue: catalogue)
    }

    func read(id: UUID, entry: RemoteFileEntry, allowStale: Bool) async throws -> CorpusFile? {
        try await cache.read(id: id, entry: entry, allowStale: allowStale)
    }

    func store(id: UUID, entry: RemoteFileEntry, file: CorpusFile) async throws {
        try await cache.store(id: id, entry: entry, file: file)
    }

    func setRetained(id: UUID, path: String, isFolder: Bool, keep: Bool) async throws {
        try await cache.setRetained(id: id, path: path, isFolder: isFolder, keep: keep)
    }

    func removeRetentionRule(id: UUID, ruleID: String) async throws {
        try await cache.removeRetentionRule(id: id, ruleID: ruleID)
    }

    func setLimit(bytes: Int) async throws { try await cache.setLimit(bytes: bytes) }
    func clearTemporary() async throws { try await cache.clearTemporary() }

    func release(id: UUID, path: String, isFolder: Bool) async throws {
        try await cache.release(id: id, path: path, isFolder: isFolder)
    }

    func remove(id: UUID) async throws { try await cache.remove(id: id) }
    func usage() async throws -> OnDemandCacheUsage { try await cache.usage() }
}

private actor DisplayNameRecoveryCredentials: DeviceCredentialStore {
    private var values: [UUID: String]

    init(values: [UUID: String]) { self.values = values }
    func credential(deviceID: UUID) async throws -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) async throws { values[deviceID] = credential }
    func remove(deviceID: UUID) async throws { values[deviceID] = nil }
}
