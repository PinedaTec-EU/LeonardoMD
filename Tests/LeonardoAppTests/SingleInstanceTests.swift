import XCTest
@testable import LeonardoApp

@MainActor
final class SingleInstanceTests: XCTestCase {
    func testOwnershipUsesProductIdentityAcrossBundleCopies() {
        XCTAssertEqual(SingleInstance.serviceName, "eu.pinedatec.LeonardoMD.launch")
    }

    func testElectionForwardingAcknowledgementAndOwnershipRelease() async throws {
        let name = "eu.pinedatec.LeonardoMD.test.\(UUID().uuidString)"
        let owner = SingleInstance(name: name)
        defer { owner.stop() }
        XCTAssertEqual(try owner.claim(), .primary)
        let other = SingleInstance(name: name)
        defer { other.stop() }
        XCTAssertEqual(try other.claim(), .secondary)
        let url = URL(fileURLWithPath: "/tmp/a document with spaces.md")
        var received: [[URL]] = []
        owner.receive = { received.append($0) }
        try await SingleInstance.forward([url], name: name)
        try await SingleInstance.forward([], name: name)
        XCTAssertEqual(received, [[url], []])
        other.stop()
        XCTAssertEqual(try SingleInstance(name: name).claim(), .secondary)
        owner.stop()
        XCTAssertEqual(try other.claim(), .primary)
    }

    func testConcurrentRequestsAllReceiveAcknowledgement() async throws {
        let name = "eu.pinedatec.LeonardoMD.test.\(UUID().uuidString)"
        let owner = SingleInstance(name: name)
        defer { owner.stop() }
        XCTAssertEqual(try owner.claim(), .primary)
        var received: Set<URL> = []
        owner.receive = { received.formUnion($0) }
        let urls = (0..<12).map { URL(fileURLWithPath: "/tmp/launch-\($0).md") }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask { try await SingleInstance.forward([url], name: name) }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(received, Set(urls))
    }

    func testMissingOwnerDoesNotSilentlyAcceptDocuments() async {
        let name = "eu.pinedatec.LeonardoMD.test.\(UUID().uuidString)"
        do {
            try await SingleInstance.forward([], name: name)
            XCTFail("A missing owner must fail forwarding")
        } catch {
            guard case SingleInstance.LaunchError.unavailable = error else {
                XCTFail("Unexpected failure: \(error)")
                return
            }
        }
    }
}
