import Combine
import XCTest
@testable import LeonardoRender

@MainActor
final class MarkdownPreviewControllerTests: XCTestCase {
    func testReadyPublicationIsDeferredAndDeduplicatedWhilePreservingTransitions() async throws {
        let controller = MarkdownPreviewController()
        let host = MarkdownPreviewHost(frame: .zero)
        controller.attach(host)

        var publications: [Bool] = []
        let observation = controller.$isReady.dropFirst().sink { publications.append($0) }
        defer { observation.cancel() }

        let ready = try XCTUnwrap(host.onReady)
        await waitForPublication(controller, value: true) {
            ready(true)
            ready(true)
            XCTAssertFalse(controller.isReady, "Readiness must not publish synchronously from the host callback")
        }
        XCTAssertTrue(controller.isReady)
        XCTAssertEqual(publications, [true])

        await assertNoPublication(controller) {
            ready(true)
        }
        XCTAssertEqual(publications, [true], "Duplicate readiness must not emit a second publication")

        await waitForPublication(controller, value: false) {
            ready(false)
            XCTAssertTrue(controller.isReady)
            controller.attach(host)
        }
        XCTAssertFalse(controller.isReady)
        XCTAssertEqual(publications, [true, false])

        await assertNoPublication(controller) {
            ready(false)
        }
        XCTAssertEqual(publications, [true, false])
    }

    func testReadyCallbackFromReplacedHostIsIgnored() async throws {
        let controller = MarkdownPreviewController()
        let oldHost = MarkdownPreviewHost(frame: .zero)
        let newHost = MarkdownPreviewHost(frame: .zero)
        controller.attach(oldHost)
        let oldReady = try XCTUnwrap(oldHost.onReady)
        await waitForPublication(controller, value: true) {
            oldReady(true)
        }
        XCTAssertTrue(controller.isReady)

        await waitForPublication(controller, value: false) {
            controller.attach(newHost)
            XCTAssertTrue(controller.isReady, "The replacement reset is deferred until the current view update ends")
        }
        XCTAssertFalse(controller.isReady)

        await assertNoPublication(controller) {
            oldReady(true)
        }
        XCTAssertFalse(controller.isReady)

        let newReady = try XCTUnwrap(newHost.onReady)
        await waitForPublication(controller, value: true) {
            newReady(true)
            XCTAssertFalse(controller.isReady)
        }
        XCTAssertTrue(controller.isReady)
    }

    private func waitForPublication(
        _ controller: MarkdownPreviewController,
        value: Bool,
        action: () -> Void
    ) async {
        let expectation = expectation(description: "Markdown preview publishes readiness \(value)")
        let observation = controller.$isReady
            .dropFirst()
            .filter { $0 == value }
            .prefix(1)
            .sink { _ in expectation.fulfill() }
        action()
        await fulfillment(of: [expectation], timeout: 1)
        observation.cancel()
    }

    private func assertNoPublication(
        _ controller: MarkdownPreviewController,
        action: () -> Void
    ) async {
        let expectation = expectation(description: "Duplicate readiness remains coalesced")
        expectation.isInverted = true
        let observation = controller.$isReady
            .dropFirst()
            .sink { _ in expectation.fulfill() }
        action()
        await fulfillment(of: [expectation], timeout: 0.1)
        observation.cancel()
    }

}
