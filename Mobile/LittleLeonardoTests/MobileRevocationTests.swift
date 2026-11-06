import XCTest
import LeonardoSync
@testable import LittleLeonardo

final class MobileRevocationTests: XCTestCase {
    private let connectionID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let deviceID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    private let otherConnectionID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
    private let otherDeviceID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!

    private func connection(id: UUID? = nil, device: UUID? = nil, projectIDs: Set<UUID> = [],
                            endpoint: URL? = nil) -> MobileDirectConnection {
        MobileDirectConnection(connectionID: id ?? connectionID, deviceID: device ?? deviceID,
                               endpoint: endpoint ?? URL(string: "https://127.0.0.1:40882")!,
                               fingerprint: Data(repeating: 7, count: 32), projectIDs: projectIDs,
                               comparisonCode: "123456", capabilities: [.rubricExchangeV1])
    }

    func testPreflightPersistenceFailureMakesZeroNetworkCalls() async throws {
        let journal = ThrowingJournal()
        let client = MobileRevocationClient(journal: journal)
        var networkCalls = 0

        do {
            _ = try await client.withPreflight(for: connection()) {
                networkCalls += 1
                return true
            }
            XCTFail("A failed write-ahead marker must reject the operation")
        } catch {
            XCTAssertEqual(networkCalls, 0)
        }
    }

    func testCrashMarkerSurvivesTransientRestartAndClearsOnlyAfterAuthorizedStatus() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = MobileRevocationJournal(url: root.appendingPathComponent("revocation.json"),
                                            sessionID: UUID())
        let ticket = try first.begin(connectionID: connectionID, deviceID: deviceID,
                                     fingerprint: connection().fingerprint, projectIDs: [])

        let reopened = MobileRevocationJournal(url: root.appendingPathComponent("revocation.json"),
                                               sessionID: UUID())
        let transientTicket = try reopened.begin(connectionID: connectionID, deviceID: deviceID,
                                                  fingerprint: connection().fingerprint, projectIDs: [])
        try reopened.complete(transientTicket, outcome: .transient)
        XCTAssertEqual(try reopened.load().first?.state, .uncertain)

        let statusTicket = try reopened.begin(connectionID: connectionID, deviceID: deviceID,
                                               fingerprint: connection().fingerprint, projectIDs: [])
        try reopened.complete(statusTicket, outcome: .authorized)
        XCTAssertTrue(try reopened.load().isEmpty,
                      "Only a successful authenticated STATUS may clear the inherited marker")
        _ = ticket
    }

    func testDeniedMarkerHidesOnlyItsConnectionAndLateAuthorizationCannotClearIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = MobileRevocationJournal(url: root.appendingPathComponent("revocation.json"))
        let project = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
        let revoked = connection(projectIDs: [project])
        let unrelated = connection(id: otherConnectionID, device: otherDeviceID, projectIDs: [UUID()])
        try journal.recordDenied(connectionID: revoked.connectionID, deviceID: revoked.deviceID,
                                 fingerprint: revoked.fingerprint, projectIDs: [project])

        let recovery = MobileDirectConnectionStore.applyRevocationMarkers(try journal.load(),
                                                                           to: [revoked, unrelated])
        XCTAssertTrue(recovery.connections[0].revoked)
        XCTAssertFalse(recovery.connections[1].revoked)
        XCTAssertTrue(recovery.quarantinedConnectionIDs.isEmpty)
        XCTAssertThrowsError(try journal.begin(connectionID: revoked.connectionID, deviceID: revoked.deviceID,
                                               fingerprint: revoked.fingerprint, projectIDs: [project])) { error in
            XCTAssertEqual(error as? SyncError, .revoked)
        }

        var authorization = MobileAuthorizationGenerations()
        let before = authorization[revoked.connectionID]
        authorization.confirmDenied(connectionID: revoked.connectionID, projectIDs: [project])
        authorization.clearQuarantine(connectionID: revoked.connectionID)
        XCTAssertGreaterThan(authorization[revoked.connectionID], before)
        XCTAssertTrue(authorization.isDenied(connectionID: revoked.connectionID))
        XCTAssertEqual(authorization.projectsPendingPurge(for: revoked.connectionID), [project])
    }

    func testTransientCompletionDoesNotDenyConnection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = MobileRevocationJournal(url: root.appendingPathComponent("revocation.json"))
        let client = MobileRevocationClient(journal: journal)

        do {
            _ = try await client.withPreflight(for: connection()) { () -> Bool in
                throw TestFailure.offline
            }
            XCTFail("The injected offline result must propagate")
        } catch TestFailure.offline { }

        XCTAssertTrue(try journal.load().isEmpty)
        var authorization = MobileAuthorizationGenerations()
        XCTAssertFalse(authorization.isDenied(connectionID: connectionID))
    }

    func testLateAuthorizedOrTransientCompletionCannotClearMonotonicDeny() async throws {
        for transient in [false, true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let backing = MobileRevocationJournal(url: root.appendingPathComponent("revocation.json"))
            let journal = FailingJournal(backing: backing, failCompletion: true, failRecordDenied: true)
            let client = MobileRevocationClient(journal: journal)
            let state = LockedFlag()
            let gate = RevocationGate()
            let started = LockedFlag()
            let startedExpectation = ExpectationSignal(expectation(description: "revocation operation started"))
            let task = Task<SyncError?, Never> {
                do {
                    let value = connection()
                    let token = MobileConnectionToken(connectionID: value.connectionID, deviceID: value.deviceID,
                                                      fingerprint: value.fingerprint, cacheEpoch: 0,
                                                      authorizationGeneration: 0)
                    _ = try await client.withAuthenticatedConnection(value, token: token,
                        credentials: TestCredentials(values: [deviceID: "credential"], failRemove: false),
                        isCurrent: { !state.value }, onDenied: { _ in }, operation: { _ in
                        started.value = true
                        startedExpectation.fulfill()
                        await gate.wait()
                        if transient { throw RevocationTestFailure.offline }
                        return true
                        }, status: { _, _, _ in
                            DirectDeviceStatus(access: .authorized, projects: [], capabilities: [.rubricExchangeV1])
                        }
                    )
                    return nil
                } catch let error as SyncError {
                    return error
                } catch {
                    return nil
                }
            }
            await fulfillment(of: [startedExpectation.expectation], timeout: 2)
            guard started.value else {
                await gate.open()
                _ = await task.value
                XCTFail("The revocation operation did not reach its gate")
                continue
            }

            state.value = true
            XCTAssertThrowsError(try journal.recordDenied(connectionID: connectionID, deviceID: deviceID,
                                                          fingerprint: connection().fingerprint, projectIDs: []))
            await gate.open()
            let completion = await task.value
            XCTAssertEqual(completion, .revoked)

            let reopened = MobileRevocationJournal(url: root.appendingPathComponent("revocation.json"),
                                                   sessionID: UUID())
            let markers = try reopened.load()
            XCTAssertEqual(markers.first?.state, .uncertain,
                           "A late \(transient ? "transient" : "authorized") completion must not clear uncertainty")
            XCTAssertTrue(MobileDirectConnectionStore.applyRevocationMarkers(markers, to: [connection()])
                .quarantinedConnectionIDs.contains(connectionID))
        }
    }

    @MainActor
    func testWriteAheadMarkerSurvivesNormalPersistenceFailuresOnReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("LittleLeonardo", isDirectory: true)
        let corpusRoot = support.appendingPathComponent("Corpus", isDirectory: true)
        let journalURL = support.appendingPathComponent("revocation.json")
        let journal = MobileRevocationJournal(url: journalURL)
        let project = UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!
        let unrelatedProjectID = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!
        let value = connection(projectIDs: [project], endpoint: URL(string: "https://127.0.0.1:9")!)
        let unrelated = connection(id: otherConnectionID, device: otherDeviceID,
                                   projectIDs: [unrelatedProjectID], endpoint: URL(string: "https://127.0.0.1:9")!)
        let offlineProject = try OfflineProject(id: project, name: "Offline direct",
                                                mode: .direct, scope: try CorpusScope(folder: ""),
                                                snapshot: CorpusSnapshot(revision: "r1",
                                                    files: [CorpusFile(path: "docs/read.md", content: Data("cached".utf8))]))
        let unrelatedOfflineProject = try OfflineProject(id: unrelatedProjectID, name: "Unrelated direct",
                                                         mode: .direct, scope: try CorpusScope(folder: ""),
                                                         snapshot: CorpusSnapshot(revision: "r1",
                                                             files: [CorpusFile(path: "docs/other.md", content: Data("unrelated".utf8))]))
        let corpus = OfflineCorpusStore(root: corpusRoot)
        try await corpus.save(offlineProject)
        try await corpus.save(unrelatedOfflineProject)

        let connectionURL = support.appendingPathComponent("connections.json")
        let connectionStore = MobileDirectConnectionStore(url: connectionURL)
        try connectionStore.save([value, unrelated])
        let originalConnections = support.appendingPathComponent("connections-original.json")
        try FileManager.default.copyItem(at: connectionURL, to: originalConnections)
        let projectURL = corpusRoot.appendingPathComponent(project.uuidString + ".json")
        let originalProject = support.appendingPathComponent("project-original.json")
        try FileManager.default.copyItem(at: projectURL, to: originalProject)
        _ = try journal.begin(connectionID: value.connectionID, deviceID: value.deviceID,
                              fingerprint: value.fingerprint, projectIDs: value.projectIDs)
        let failingJournal = FailingJournal(backing: journal, failCompletion: true, failRecordDenied: true)

        // Arm both ordinary persistence surfaces before invoking the real
        // library revocation handler. The independent marker is already on
        // disk from the authenticated-operation preflight above.
        let connectionFaultTarget = support.appendingPathComponent("connection-fault-target")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data("fault\n".utf8).write(to: connectionFaultTarget, options: .atomic)
        let projectFaultTarget = support.appendingPathComponent("project-fault-target")
        try Data("fault\n".utf8).write(to: projectFaultTarget, options: .atomic)
        try FileManager.default.removeItem(at: projectURL)
        try FileManager.default.createSymbolicLink(at: projectURL, withDestinationURL: projectFaultTarget)
        let credentials = TestCredentials(values: [deviceID: "old-credential"], failRemove: true)
        let current = MobileLibrary(rootURL: corpusRoot, credentials: credentials, revocationJournal: failingJournal)
        await current.reload()
        try FileManager.default.removeItem(at: connectionURL)
        try FileManager.default.createSymbolicLink(at: connectionURL, withDestinationURL: connectionFaultTarget)
        let token = MobileConnectionToken(connectionID: value.connectionID, deviceID: value.deviceID,
                                          fingerprint: value.fingerprint, cacheEpoch: 0,
                                          authorizationGeneration: 0)
        await current.handleConfirmedRevocation(for: token, ticket: nil,
                                                message: "Revoked in fault-injection test")
        XCTAssertNotNil(current.error, "The handler must surface the injected persistence failures")
        XCTAssertEqual(try journal.load().first?.state, .uncertain,
                       "The write-ahead marker must remain when deny completion also fails")
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path),
                      "The cache remains on disk when its purge adapter fails")
        XCTAssertFalse(current.projects.contains(where: { $0.id == project }))
        XCTAssertTrue(current.projects.contains(where: { $0.id == unrelatedProjectID }),
                      "An unrelated direct cache must survive the revocation")

        // Restore the regular files only to prove that a same-process reload
        // still honors the in-memory deny overlay after the handler failed.
        try FileManager.default.removeItem(at: connectionURL)
        try FileManager.default.copyItem(at: originalConnections, to: connectionURL)
        try FileManager.default.removeItem(at: projectURL)
        try FileManager.default.copyItem(at: originalProject, to: projectURL)
        await current.reload()
        XCTAssertFalse(current.projects.contains(where: { $0.id == project }))
        XCTAssertTrue(current.projects.contains(where: { $0.id == unrelatedProjectID }))

        // Recreate the old on-disk snapshot/cache before a fresh instance.
        // The failed post-response writes therefore cannot be mistaken for a
        // successful revoke; only the pre-existing marker can quarantine it.
        try FileManager.default.removeItem(at: connectionURL)
        try FileManager.default.copyItem(at: originalConnections, to: connectionURL)
        try FileManager.default.removeItem(at: projectURL)
        try FileManager.default.copyItem(at: originalProject, to: projectURL)
        let freshCredentials = TestCredentials(values: [deviceID: "old-credential"], failRemove: true)
        let fresh = MobileLibrary(rootURL: corpusRoot, credentials: freshCredentials, revocationJournal: failingJournal)
        await fresh.reload()
        XCTAssertFalse(fresh.projects.contains(where: { $0.id == project }))
        XCTAssertTrue(fresh.projects.contains(where: { $0.id == unrelatedProjectID }))
        await fresh.synchronize()
        await fresh.pollRubricRequests()
        XCTAssertTrue(fresh.pendingRubricRequests.isEmpty)
        XCTAssertEqual(try journal.load().first?.state, .uncertain)
        let retainedCredential = try await freshCredentials.credential(deviceID: deviceID)
        XCTAssertEqual(retainedCredential, "old-credential")
    }

    private enum TestFailure: Error { case offline }
}

private struct ThrowingJournal: MobileRevocationJournalStore {
    func load() throws -> [MobileRevocationMarker] { [] }

    func begin(connectionID: UUID, deviceID: UUID, fingerprint: Data,
               projectIDs: Set<UUID>) throws -> MobileRevocationTicket {
        throw SyncError.invalidPath
    }

    func complete(_ ticket: MobileRevocationTicket, outcome: MobileRevocationOutcome) throws { }

    func recordDenied(connectionID: UUID, deviceID: UUID, fingerprint: Data,
                      projectIDs: Set<UUID>) throws { }
}

private final class FailingJournal: MobileRevocationJournalStore, @unchecked Sendable {
    private let backing: MobileRevocationJournal
    private let failCompletion: Bool
    private let failRecordDenied: Bool

    init(backing: MobileRevocationJournal, failCompletion: Bool = false, failRecordDenied: Bool = false) {
        self.backing = backing
        self.failCompletion = failCompletion
        self.failRecordDenied = failRecordDenied
    }

    func load() throws -> [MobileRevocationMarker] { try backing.load() }

    func begin(connectionID: UUID, deviceID: UUID, fingerprint: Data,
               projectIDs: Set<UUID>) throws -> MobileRevocationTicket {
        try backing.begin(connectionID: connectionID, deviceID: deviceID,
                          fingerprint: fingerprint, projectIDs: projectIDs)
    }

    func complete(_ ticket: MobileRevocationTicket, outcome: MobileRevocationOutcome) throws {
        if failCompletion { throw RevocationTestFailure.persistence }
        try backing.complete(ticket, outcome: outcome)
    }

    func recordDenied(connectionID: UUID, deviceID: UUID, fingerprint: Data,
                      projectIDs: Set<UUID>) throws {
        if failRecordDenied { throw RevocationTestFailure.persistence }
        try backing.recordDenied(connectionID: connectionID, deviceID: deviceID,
                                 fingerprint: fingerprint, projectIDs: projectIDs)
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    var value: Bool {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}

private final class ExpectationSignal: @unchecked Sendable {
    let expectation: XCTestExpectation

    init(_ expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func fulfill() {
        expectation.fulfill()
    }
}

private actor RevocationGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}

private enum RevocationTestFailure: Error { case offline; case persistence }

private actor TestCredentials: DeviceCredentialStore {
    private var values: [UUID: String]
    private let failRemove: Bool

    init(values: [UUID: String], failRemove: Bool) {
        self.values = values
        self.failRemove = failRemove
    }

    func credential(deviceID: UUID) async throws -> String? { values[deviceID] }
    func save(_ credential: String, deviceID: UUID) async throws { values[deviceID] = credential }
    func remove(deviceID: UUID) async throws {
        if failRemove { throw RevocationTestFailure.persistence }
        values.removeValue(forKey: deviceID)
    }
}
