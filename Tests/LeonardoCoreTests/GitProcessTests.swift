import Foundation
import XCTest
@testable import LeonardoCore

final class GitProcessTests: XCTestCase {
    func testBothStreamsAreCompleteAfterFastExit() async throws {
        let directory = try TemporaryDirectory()
        let executable = directory.url.appendingPathComponent("output.sh")
        try "#!/bin/sh\nprintf 'branch.ab +0 -1\\0'\nprintf 'complete error stream' >&2\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let runner = GitProcessRunner(executableURL: executable)
        for _ in 0..<50 {
            let result = try await runner.run(arguments: [], at: directory.url)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertEqual(result.stdout, "branch.ab +0 -1\0")
            XCTAssertEqual(result.stderr, "complete error stream")
        }
    }

    func testLargeStreamsDrainConcurrentlyWithoutTruncation() async throws {
        let directory = try TemporaryDirectory()
        let executable = directory.url.appendingPathComponent("large-output.sh")
        try "#!/bin/sh\ndd if=/dev/zero bs=1048576 count=2 2>/dev/null\ndd if=/dev/zero bs=1048576 count=2 1>&2 2>/dev/null\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let result = try await GitProcessRunner(executableURL: executable).run(arguments: [], at: directory.url)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.utf8.count, 2 * 1024 * 1024)
        XCTAssertEqual(result.stderr.utf8.count, 2 * 1024 * 1024)
    }

    func testLaunchFailureReturnsWithoutWaitingForPipeReaders() async throws {
        let directory = try TemporaryDirectory()
        do {
            _ = try await GitProcessRunner(executableURL: directory.url.appendingPathComponent("missing")).run(arguments: [], at: directory.url)
            XCTFail("Expected launch failure")
        } catch { }
    }
}
