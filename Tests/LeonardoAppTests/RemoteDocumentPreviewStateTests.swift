import XCTest
import LeonardoSync
@testable import LeonardoSyncUI

final class RemoteDocumentPreviewStateTests: XCTestCase {
    private let projectID = UUID()
    private func request(_ file: CorpusFile) -> RemoteDocumentPreviewRequest {
        .init(projectID: projectID, path: file.path, catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: file)]))
    }
    private let a = CorpusFile(path: "note.md", content: Data("old".utf8))
    private let b = CorpusFile(path: "note.md", content: Data("new".utf8))

    func testCatalogueTransitionHidesBytesAndImagesBeforeReplacementTaskStarts() {
        var state = RemoteDocumentPreviewState()
        let first = request(a)
        let next = request(b)
        let ticket = state.begin(first)
        state.receive(a, ticket: ticket)
        state.receiveImage(Data([1]), path: "image.png", ticket: ticket)
        XCTAssertEqual(state.content(for: first), a)
        XCTAssertEqual(state.assets(for: first).count, 1)
        XCTAssertNil(state.content(for: next))
        XCTAssertTrue(state.assets(for: next).isEmpty)
        XCTAssertNil(state.content(for: .init(projectID: projectID, path: a.path, catalogue: nil)))
    }

    func testFailedReplacementShowsErrorWithoutObsoleteContent() {
        var state = RemoteDocumentPreviewState()
        let first = request(a)
        let next = request(b)
        let initial = state.begin(first)
        state.receive(a, ticket: initial)
        let replacement = state.begin(next)
        XCTAssertNil(state.content(for: next))
        state.fail("unavailable", ticket: replacement)
        XCTAssertNil(state.content(for: next))
        XCTAssertEqual(state.error(for: next), "unavailable")
        XCTAssertTrue(state.assets(for: next).isEmpty)
    }

    func testObsoleteCompletionCannotRestoreBytesImagesOrErrorEvenForSameCatalogueRetry() {
        var state = RemoteDocumentPreviewState()
        let catalogue = request(b)
        let old = state.begin(catalogue)
        let current = state.begin(catalogue)
        state.receive(b, ticket: current)
        state.receive(a, ticket: old)
        state.receiveImage(Data([1]), path: "image.png", ticket: old)
        state.fail("old failure", ticket: old)
        XCTAssertEqual(state.content(for: catalogue), b)
        XCTAssertNil(state.error(for: catalogue))
        XCTAssertTrue(state.assets(for: catalogue).isEmpty)
    }

    func testDifferentDocumentOrProjectCannotReusePresentationWithSameCatalogue() {
        var state = RemoteDocumentPreviewState()
        let initial = request(a)
        let ticket = state.begin(initial)
        state.receive(a, ticket: ticket)
        state.fail("initial failure", ticket: ticket)
        for other in [
            RemoteDocumentPreviewRequest(projectID: projectID, path: "other.md", catalogue: initial.catalogue),
            RemoteDocumentPreviewRequest(projectID: UUID(), path: a.path, catalogue: initial.catalogue)
        ] {
            XCTAssertNil(state.content(for: other))
            XCTAssertNil(state.error(for: other))
            XCTAssertTrue(state.assets(for: other).isEmpty)
        }
    }

}
