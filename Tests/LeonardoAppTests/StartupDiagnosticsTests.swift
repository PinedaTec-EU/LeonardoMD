import XCTest
@testable import LeonardoApp

final class StartupDiagnosticsTests: XCTestCase {
    @MainActor
    func testMetadataCannotBreakJSONLineFraming() throws {
        let context = StartupDiagnostics.Context(
            pid: 42, parentPID: 7, startedAt: 1,
            bundleIdentifier: "test.bundle\nforged-event", version: "1\"2", build: "unknown",
            isAppBundle: true, operatingSystem: "test", architecture: "arm64"
        )
        var output = Data()
        let diagnostics = StartupDiagnostics(context: context) { output.append($0) }
        diagnostics.record(.applicationInitializing)
        XCTAssertEqual(output.filter { $0 == 0x0A }.count, 1)
        XCTAssertEqual(output.last, 0x0A)
        let record = try JSONDecoder().decode(StartupDiagnostics.Record.self, from: output)
        XCTAssertEqual(record.context.bundleIdentifier, context.bundleIdentifier)
        XCTAssertEqual(record.phase, .applicationInitializing)
        XCTAssertTrue(record.isMainThread)
        XCTAssertGreaterThanOrEqual(record.elapsedMilliseconds, 0)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        let metadata = try XCTUnwrap(object["context"] as? [String: Any])
        XCTAssertEqual(Set(metadata.keys), Set([
            "pid", "parentPID", "startedAt", "bundleIdentifier", "version", "build",
            "isAppBundle", "operatingSystem", "architecture"
        ]))
    }

    @MainActor
    func testUnavailableStandardErrorDoesNotInterruptStartup() {
        struct ClosedStream: Error {}
        var attempts = 0
        let diagnostics = StartupDiagnostics { _ in
            attempts += 1
            throw ClosedStream()
        }
        diagnostics.record(.processStarted)
        diagnostics.record(.applicationInitializing)
        XCTAssertEqual(attempts, 2)
    }
}
