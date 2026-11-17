import XCTest
@testable import LeonardoSync

final class DesktopPeerLibraryAccessTests: XCTestCase {
    func testDefaultFileReadFailsBeforeFetchingBytes() async throws {
        let counter = FileReadCounter()
        let file = CorpusFile(path: "docs/read.md", content: Data("protected".utf8))
        let access = DefaultFileReadFixture(fileValue: file, counter: counter)

        do {
            _ = try await access.fileRead(connectionID: UUID(), projectID: UUID(),
                                          entry: RemoteFileEntry(file: file))
            XCTFail("An adapter without metadata-first authorization must fail closed")
        } catch {
            XCTAssertEqual(error as? DesktopPeerLibraryError, .metadataFirstAuthorizationRequired)
        }

        let fileCalls = await counter.value
        XCTAssertEqual(fileCalls, 0, "Protected bytes must not be fetched before authorization")
    }
}

private struct DefaultFileReadFixture: DesktopPeerLibraryAccess {
    let fileValue: CorpusFile
    let counter: FileReadCounter

    func connections() async throws -> [DesktopPeerConnection] { [] }
    func copies() async throws -> [DesktopPeerCopy] { [] }
    func enroll(endpoint: URL, fingerprint: Data?, invitation: PairingInvitation?,
                name: String) async throws -> DesktopPeerConnection {
        throw DesktopPeerLibraryError.unknownConnection
    }
    func refresh(connectionID: UUID) async throws -> DirectDeviceStatus {
        DirectDeviceStatus(access: .authorized, projects: [])
    }
    func catalogue(connectionID: UUID, projectID: UUID) async throws -> RemoteProjectCatalogue { .init(files: []) }
    func file(connectionID: UUID, projectID: UUID, entry: RemoteFileEntry) async throws -> CorpusFile {
        await counter.increment()
        return fileValue
    }
    func importProject(connectionID: UUID, projectID: UUID) async throws -> DesktopPeerCopy {
        throw DesktopPeerLibraryError.unknownCopy
    }
    func open(copyID: UUID) async throws -> URL { URL(fileURLWithPath: "/tmp/unopened") }
    func pendingProposal(copyID: UUID) async throws -> DesktopPeerPendingProposal? { nil }
    func pendingReceipt(copyID: UUID) async throws -> DesktopPeerProposalReceipt? { nil }
    func acknowledge(copyID: UUID, receipt: DesktopPeerProposalReceipt,
                     buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerAcceptanceResult {
        throw DesktopPeerLibraryError.unknownCopy
    }
    func send(copyID: UUID, buffers: [OpenDocumentBuffer]) async throws -> UUID? { nil }
    func compare(copyID: UUID, buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerComparison {
        throw DesktopPeerLibraryError.unknownCopy
    }
}

private actor FileReadCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
