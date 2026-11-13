import XCTest
import LeonardoCore
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
        let authorization = MobileAuthorizationGenerations()
        XCTAssertFalse(authorization.isDenied(connectionID: connectionID))
    }

    @MainActor
    func testOnDemandForbiddenResponseRechecksStatusBeforeRecordingRevocation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = MobileRevocationJournal(url: root.appendingPathComponent("revocation.json"))
        let client = MobileRevocationClient(journal: journal)
        let value = connection(projectIDs: [UUID()])
        let token = MobileConnectionToken(connectionID: value.connectionID, deviceID: value.deviceID,
                                          fingerprint: value.fingerprint, cacheEpoch: 0,
                                          authorizationGeneration: 0)
        let credentials = TestCredentials(values: [value.deviceID: "credential"], failRemove: false)
        let statusCalls = LockedCounter()
        let deniedCalls = LockedCounter()

        do {
            _ = try await client.withAuthenticatedConnection(value, token: token,
                credentials: credentials, isCurrent: { true }, onDenied: { ticket in
                    deniedCalls.increment()
                    try? client.finish(ticket, outcome: .denied)
                }, operation: { _ in
                    throw SyncError.httpAccessDenied(operation: .file, status: 403)
                }, status: { _, _, _ in
                    statusCalls.increment()
                    return DirectDeviceStatus(access: statusCalls.value == 1 ? .authorized : .revoked,
                                              projects: [], capabilities: [.rubricExchangeV1])
                }
            )
            XCTFail("A 403 followed by confirmed device revocation must stop the operation")
        } catch let error as SyncError {
            XCTAssertEqual(error, .revoked)
        }

        XCTAssertEqual(statusCalls.value, 2, "The 403 must trigger an authenticated STATUS recheck")
        XCTAssertEqual(deniedCalls.value, 1, "Confirmed revocation must trigger durable cleanup once")
        XCTAssertEqual(try journal.load().first?.state, .denied)
    }

    @MainActor
    func testProductionOpenKeepsOtherGrantedProjectAfterProjectWithdrawal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("LittleLeonardo", isDirectory: true)
        let corpusRoot = support.appendingPathComponent("Corpus", isDirectory: true)
        let firstProjectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondProjectID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let firstDescriptor = SharedProjectDescriptor(id: firstProjectID, name: "First",
            scope: try CorpusScope(folder: ""))
        let secondDescriptor = SharedProjectDescriptor(id: secondProjectID, name: "Second",
            scope: try CorpusScope(folder: ""))
        let firstFile = CorpusFile(path: "docs/first.md", content: Data("first retained".utf8))
        let firstCurrentFile = CorpusFile(path: firstFile.path, content: Data("new source revision".utf8))
        let secondFile = CorpusFile(path: "docs/second.md", content: Data("second retained".utf8))
        let firstEntry = RemoteFileEntry(file: firstFile)
        let firstCurrentEntry = RemoteFileEntry(file: firstCurrentFile)
        let secondEntry = RemoteFileEntry(file: secondFile)
        let descriptors = [firstDescriptor, secondDescriptor]
        let value = MobileDirectConnection(connectionID: connectionID, deviceID: deviceID,
            endpoint: URL(string: "https://127.0.0.1:9")!, fingerprint: Data(repeating: 7, count: 32),
            projectIDs: [firstProjectID, secondProjectID], comparisonCode: nil,
            capabilities: [], projectDescriptors: descriptors,
            acceptedProjectIDs: [firstProjectID, secondProjectID])
        let credentials = TestCredentials(values: [deviceID: "credential"], failRemove: false)
        try MobileDirectConnectionStore(url: support.appendingPathComponent("connections.json")).save([value])
        let statusCalls = LockedCounter()
        let library = MobileLibrary(rootURL: corpusRoot, credentials: credentials,
            revocationJournal: MobileRevocationJournal(url: support.appendingPathComponent("revocation.json")),
            statusRequest: { _, _, _ in
                statusCalls.increment()
                let projects = statusCalls.value == 1 ? descriptors : [secondDescriptor]
                return DirectDeviceStatus(access: .authorized, projects: projects)
            },
            fileRequest: { _, _, _, _, _ in
                throw SyncError.httpAccessDenied(operation: .file, status: 403)
            })
        library.connections = [value]
        let firstOffline = try OfflineProject(id: firstProjectID, name: "First", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "catalogue", files: []))
        let secondOffline = try OfflineProject(id: secondProjectID, name: "Second", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "catalogue", files: []))
        library.projects = [firstOffline, secondOffline]
        try await library.downloads.update(id: firstProjectID, descriptor: firstDescriptor,
            catalogue: RemoteProjectCatalogue(files: [firstEntry]))
        library.downloads.fetch = { _, entry in entry == firstEntry ? firstFile : secondFile }
        await library.downloads.retain(id: firstProjectID, path: firstFile.path, isFolder: false, keep: true)
        _ = try await library.downloads.open(id: firstProjectID, path: firstFile.path)
        try await library.downloads.update(id: firstProjectID, descriptor: firstDescriptor,
            catalogue: RemoteProjectCatalogue(files: [firstCurrentEntry]))
        try await library.downloads.update(id: secondProjectID, descriptor: secondDescriptor,
            catalogue: RemoteProjectCatalogue(files: [secondEntry]))
        _ = try await library.downloads.open(id: secondProjectID, path: secondFile.path)
        library.downloads.fetch = { id, entry in try await library.fetchDownload(projectID: id, entry: entry) }

        do {
            _ = try await library.downloads.open(id: firstProjectID, path: firstCurrentFile.path)
            XCTFail("A project withdrawn between STATUS and file access must not open its retained bytes")
        } catch let error as SyncError { XCTAssertEqual(error, .revoked) }
        catch { XCTFail("Expected withdrawal to fail the in-flight cached open: \(error)") }

        XCTAssertEqual(statusCalls.value, 2)
        let updated = try XCTUnwrap(library.connections.first)
        XCTAssertFalse(updated.revoked, "A project withdrawal must not revoke the whole device")
        XCTAssertEqual(updated.projectIDs, [secondProjectID])
        let retainedCredential = try await credentials.credential(deviceID: deviceID)
        XCTAssertEqual(retainedCredential, "credential")
        let remaining = try await library.downloads.open(id: secondProjectID, path: secondFile.path)
        XCTAssertEqual(remaining, secondFile, "The other granted project remains available offline")
    }

    @MainActor
    func testProductionOpenRemovesAllProjectAccessWhenStatusBecomesPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("LittleLeonardo", isDirectory: true)
        let corpusRoot = support.appendingPathComponent("Corpus", isDirectory: true)
        let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let descriptor = SharedProjectDescriptor(id: projectID, name: "Granted",
            scope: try CorpusScope(folder: ""))
        let oldFile = CorpusFile(path: "docs/note.md", content: Data("retained old bytes".utf8))
        let currentFile = CorpusFile(path: oldFile.path, content: Data("new source revision".utf8))
        let oldEntry = RemoteFileEntry(file: oldFile)
        let currentEntry = RemoteFileEntry(file: currentFile)
        let value = MobileDirectConnection(connectionID: connectionID, deviceID: deviceID,
            endpoint: URL(string: "https://127.0.0.1:9")!, fingerprint: Data(repeating: 7, count: 32),
            projectIDs: [projectID], comparisonCode: nil, capabilities: [],
            projectDescriptors: [descriptor], acceptedProjectIDs: [projectID])
        let credentials = TestCredentials(values: [deviceID: "credential"], failRemove: false)
        try MobileDirectConnectionStore(url: support.appendingPathComponent("connections.json")).save([value])
        let statusCalls = LockedCounter()
        let library = MobileLibrary(rootURL: corpusRoot, credentials: credentials,
            revocationJournal: MobileRevocationJournal(url: support.appendingPathComponent("revocation.json")),
            statusRequest: { _, _, _ in
                statusCalls.increment()
                if statusCalls.value == 1 {
                    return DirectDeviceStatus(access: .authorized, projects: [descriptor])
                }
                return DirectDeviceStatus(access: .pending, projects: [])
            },
            fileRequest: { _, _, _, _, _ in
                throw SyncError.httpAccessDenied(operation: .file, status: 403)
            })
        library.connections = [value]
        try await library.downloads.update(id: projectID, descriptor: descriptor,
            catalogue: RemoteProjectCatalogue(files: [oldEntry]))
        library.downloads.fetch = { _, _ in oldFile }
        await library.downloads.retain(id: projectID, path: oldFile.path, isFolder: false, keep: true)
        _ = try await library.downloads.open(id: projectID, path: oldFile.path)
        try await library.downloads.update(id: projectID, descriptor: descriptor,
            catalogue: RemoteProjectCatalogue(files: [currentEntry]))
        library.downloads.fetch = { id, entry in try await library.fetchDownload(projectID: id, entry: entry) }

        do {
            _ = try await library.downloads.open(id: projectID, path: currentFile.path)
            XCTFail("Pending status must make previously granted cached content unavailable")
        } catch let error as SyncError { XCTAssertEqual(error, .revoked) }
        catch { XCTFail("Expected the project cache to be denied: \(error)") }

        XCTAssertEqual(statusCalls.value, 2)
        let updated = try XCTUnwrap(library.connections.first)
        XCTAssertFalse(updated.revoked, "Pending authorization is not a device revocation")
        XCTAssertTrue(updated.projectIDs.isEmpty)
        XCTAssertTrue(updated.acceptedProjectIDs.isEmpty)
        let retainedCredential = try await credentials.credential(deviceID: deviceID)
        XCTAssertEqual(retainedCredential, "credential")
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
            let value = connection()
            let token = MobileConnectionToken(connectionID: value.connectionID, deviceID: value.deviceID,
                                              fingerprint: value.fingerprint, cacheEpoch: 0,
                                              authorizationGeneration: 0)
            let credentials = TestCredentials(values: [value.deviceID: "credential"], failRemove: false)
            let task = Task<SyncError?, Never> {
                do {
                    _ = try await client.withAuthenticatedConnection(value, token: token,
                        credentials: credentials,
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
    func testLiveOperationReloadRetainsOfflineCacheButNewSessionQuarantinesIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("LittleLeonardo", isDirectory: true)
        let corpusRoot = support.appendingPathComponent("Corpus", isDirectory: true)
        let project = UUID()
        let value = connection(projectIDs: [project])
        let cached = try OfflineProject(id: project, name: "Ordinary offline cache", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "r1",
                files: [CorpusFile(path: "read.md", content: Data("readable offline".utf8))]))
        try await OfflineCorpusStore(root: corpusRoot).save(cached)
        try MobileDirectConnectionStore(url: support.appendingPathComponent("connections.json")).save([value])
        let journalURL = support.appendingPathComponent("revocation.json")
        let journal = MobileRevocationJournal(url: journalURL)
        let credentials = TestCredentials(values: [deviceID: "credential"], failRemove: false)
        let live = MobileLibrary(rootURL: corpusRoot, credentials: credentials, revocationJournal: journal)
        await live.reload()
        XCTAssertEqual(live.projects.map(\.id), [project])

        let inFlight = try journal.begin(connectionID: value.connectionID, deviceID: value.deviceID,
            fingerprint: value.fingerprint, projectIDs: value.projectIDs)
        await live.reload()
        XCTAssertEqual(live.projects.map(\.id), [project],
                       "An overlapping reload cannot mistake a live operation for a crashed session")
        try journal.complete(inFlight, outcome: .transient)
        await live.reload()
        XCTAssertEqual(live.projects.map(\.id), [project],
                       "An ordinary offline completion must retain readable cached files")

        _ = try journal.begin(connectionID: value.connectionID, deviceID: value.deviceID,
            fingerprint: value.fingerprint, projectIDs: value.projectIDs)
        let fresh = MobileLibrary(rootURL: corpusRoot, credentials: credentials,
            revocationJournal: MobileRevocationJournal(url: journalURL))
        await fresh.reload()
        XCTAssertTrue(fresh.projects.isEmpty,
                      "A new coordinator must still quarantine uncertainty from the previous session")
        let preserved = try await OfflineCorpusStore(root: corpusRoot).load(id: project)
        XCTAssertNotNil(preserved)
    }

    @MainActor
    func testDeletedMalformedCacheIsSkippedBeforeAuthorizationFilteringAndRecoveryLoad() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("LittleLeonardo", isDirectory: true)
        let corpusRoot = support.appendingPathComponent("Corpus", isDirectory: true)
        let deletedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let authorizedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let unavailableID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let recoveryID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let authorized = try OfflineProject(id: authorizedID, name: "Authorized", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "r1",
                files: [CorpusFile(path: "read.md", content: Data("authorized".utf8))]))
        let unavailable = try OfflineProject(id: unavailableID, name: "Unavailable", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "r1",
                files: [CorpusFile(path: "read.md", content: Data("unavailable".utf8))]))
        let seed = try OfflineProject(id: recoveryID, name: "Recovery", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "r1",
                files: [CorpusFile(path: "read.md", content: Data("recovery".utf8))]))
        let corpus = OfflineCorpusStore(root: corpusRoot)
        try await corpus.save(authorized)
        try await corpus.save(unavailable)
        let seedObject = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(seed))
            as? [String: Any])
        var recoveryObject = seedObject
        recoveryObject["mode"] = SyncMode.legacyGit.rawValue
        try JSONSerialization.data(withJSONObject: recoveryObject).write(
            to: corpusRoot.appendingPathComponent(recoveryID.uuidString).appendingPathExtension("json"),
            options: .atomic)
        try FileManager.default.createDirectory(at: corpusRoot, withIntermediateDirectories: true)
        try Data("malformed late cache".utf8).write(
            to: corpusRoot.appendingPathComponent(deletedID.uuidString).appendingPathExtension("json"),
            options: .atomic)

        let active = connection(projectIDs: [authorizedID, deletedID])
        let missingCredential = connection(id: otherConnectionID, device: otherDeviceID,
                                           projectIDs: [unavailableID])
        try MobileDirectConnectionStore(url: support.appendingPathComponent("connections.json"))
            .save([active, missingCredential])
        let lifecycle = MobileProjectLifecycle(url: support.appendingPathComponent("project-removals.json"))
        try lifecycle.deleteProject(deletedID)

        let library = MobileLibrary(rootURL: corpusRoot,
            credentials: TestCredentials(values: [deviceID: "credential"], failRemove: false),
            revocationJournal: MobileRevocationJournal(url: support.appendingPathComponent("revocation.json")))
        await library.reload()

        XCTAssertNil(library.error)
        XCTAssertTrue(library.projects.contains(where: { $0.id == authorizedID }))
        XCTAssertTrue(library.projects.contains(where: { $0.id == recoveryID }),
                      "An unrelated recovery archive must remain readable")
        XCTAssertFalse(library.projects.contains(where: { $0.id == deletedID }))
        XCTAssertFalse(library.projects.contains(where: { $0.id == unavailableID }),
                       "Authorization filtering must still hide an unavailable direct project")
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
        let credentials = TestCredentials(values: [deviceID: "old-credential", otherDeviceID: "unrelated-credential"],
                                           failRemove: true)
        let current = MobileLibrary(rootURL: corpusRoot, credentials: credentials, revocationJournal: failingJournal)
        await current.reload()
        try Data("fault\n".utf8).write(to: projectFaultTarget, options: .atomic)
        try FileManager.default.removeItem(at: projectURL)
        try FileManager.default.createSymbolicLink(at: projectURL, withDestinationURL: projectFaultTarget)
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
        try? FileManager.default.removeItem(at: projectURL)
        try FileManager.default.copyItem(at: originalProject, to: projectURL)
        await current.reload()
        XCTAssertFalse(current.projects.contains(where: { $0.id == project }))
        XCTAssertTrue(current.projects.contains(where: { $0.id == unrelatedProjectID }))

        // Recreate the old on-disk snapshot/cache before a fresh instance.
        // The failed post-response writes therefore cannot be mistaken for a
        // successful revoke; only the pre-existing marker can quarantine it.
        try FileManager.default.removeItem(at: connectionURL)
        try FileManager.default.copyItem(at: originalConnections, to: connectionURL)
        try? FileManager.default.removeItem(at: projectURL)
        try FileManager.default.copyItem(at: originalProject, to: projectURL)
        let freshCredentials = TestCredentials(values: [deviceID: "old-credential", otherDeviceID: "unrelated-credential"],
                                                failRemove: true)
        let reopenedJournal = FailingJournal(backing: MobileRevocationJournal(url: journalURL),
                                             failCompletion: true, failRecordDenied: true)
        let fresh = MobileLibrary(rootURL: corpusRoot, credentials: freshCredentials, revocationJournal: reopenedJournal)
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

@MainActor
final class MobileRubricIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 20_000)

    private var rubric: LeonardoRubric {
        LeonardoRubric(strokes: [.init(color: "#224466", width: 4, style: .solid,
                                      points: [.init(x: 20, y: 80), .init(x: 180, y: 100)])])
    }

    func testSameUUIDDifferentPeerDoesNotProjectOrTouchNetwork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("LittleLeonardo", isDirectory: true)
        let corpusRoot = support.appendingPathComponent("Corpus", isDirectory: true)
        try FileManager.default.createDirectory(at: corpusRoot, withIntermediateDirectories: true)

        let connection = MobileDirectConnection(
            connectionID: UUID(), deviceID: UUID(), endpoint: URL(string: "https://127.0.0.1:9")!,
            fingerprint: Data(repeating: 7, count: 32), projectIDs: [], comparisonCode: "123456",
            capabilities: [.rubricExchangeV1])
        try MobileDirectConnectionStore(url: support.appendingPathComponent("connections.json"))
            .save([connection])

        let requestID = UUID()
        let requestA = try RubricRequest(id: requestID, targetDeviceID: connection.deviceID,
                                         requesterID: UUID(), requesterName: "Mac A",
                                         labelHint: "Firma A", createdAt: now, state: .accepted)
        let stored = MobileRubricDraft(id: requestID, connectionID: connection.connectionID,
            targetDeviceID: connection.deviceID, requesterID: requestA.requesterID,
            sourceFingerprint: connection.fingerprint, request: requestA, label: "Firma A",
            state: .accepted, updatedAt: now)
        let draftStore = MobileRubricDraftStore(url: support.appendingPathComponent("Rubrics/drafts.json"))
        try await draftStore.save(stored)

        let credentials = TestCredentials(values: [connection.deviceID: "credential"], failRemove: false)
        let library = MobileLibrary(rootURL: corpusRoot, credentials: credentials,
                                    revocationJournal: MobileRevocationJournal(
                                        url: support.appendingPathComponent("revocation.json")))
        await library.reload()

        let requestB = try RubricRequest(id: requestID, targetDeviceID: connection.deviceID,
                                         requesterID: UUID(), requesterName: "Mac B",
                                         labelHint: "Firma B", createdAt: now, state: .pending)
        XCTAssertNil(library.rubricDraft(for: requestB),
                     "A same-UUID request from another peer must not project the cached drawing")

        do {
            _ = try await library.acceptRubricRequest(requestB)
            XCTFail("A same-UUID request from another peer must be rejected before HTTP")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .conflict)
        }

        do {
            _ = try await library.submitRubric(request: requestB, label: "Firma B", rubric: rubric)
            XCTFail("A same-UUID submission from another peer must be rejected before HTTP")
        } catch {
            XCTAssertEqual(error as? RubricExchangeError, .conflict)
        }
    }

    func testSubmissionGateSharesOnlyExactImmutableOperation() async throws {
        let gate = MobileRubricSubmissionGate()
        let request = try RubricRequest(id: UUID(), targetDeviceID: UUID(), requesterID: UUID(),
                                        requesterName: "Mac", labelHint: "Firma", createdAt: now,
                                        state: .accepted)
        let differentRequest = try RubricRequest(id: request.id, targetDeviceID: request.targetDeviceID,
                                                 requesterID: UUID(), requesterName: "Other Mac",
                                                 labelHint: "Firma", createdAt: now, state: .accepted)
        let alternateRubric = LeonardoRubric(strokes: [.init(color: "#A52A2A", width: 3, style: .solid,
                                                              points: [.init(x: 40, y: 40), .init(x: 100, y: 140)])])
        let response = try RubricResponse(requestID: request.id, targetDeviceID: request.targetDeviceID,
                                          requesterID: request.requesterID, label: "Firma", rubric: rubric,
                                          submittedAt: now)
        let release = RevocationGate()
        let started = expectation(description: "submission operation started")
        let first = Task { @MainActor in
            try await gate.submit(request: request, label: "Firma", rubric: rubric) {
                started.fulfill()
                await release.wait()
                return response
            }
        }
        await fulfillment(of: [started], timeout: 2)

        for (otherRequest, otherLabel, otherRubric) in [
            (differentRequest, "Firma", rubric),
            (request, "Otra firma", rubric),
            (request, "Firma", alternateRubric)
        ] {
            do {
                _ = try await gate.submit(request: otherRequest, label: otherLabel, rubric: otherRubric) {
                    XCTFail("A conflicting operation must not join the active submission")
                    return response
                }
                XCTFail("A conflicting operation must be rejected")
            } catch {
                XCTAssertEqual(error as? RubricExchangeError, .conflict)
            }
        }

        let identical = Task { @MainActor in
            try await gate.submit(request: request, label: "Firma", rubric: rubric) {
                XCTFail("An identical concurrent operation must share the active task")
                return response
            }
        }
        await release.open()
        let firstResult = try await first.value
        let identicalResult = try await identical.value
        XCTAssertEqual(firstResult, response)
        XCTAssertEqual(identicalResult, response)
    }
}

private struct ThrowingJournal: MobileRevocationJournalStore {
    let sessionID = UUID()
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

    var sessionID: UUID { backing.sessionID }

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

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int { lock.withLock { storedValue } }

    func increment() {
        lock.withLock { storedValue += 1 }
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
