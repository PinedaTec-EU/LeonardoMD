import XCTest
@testable import LeonardoCore

final class ProcessFileLockTests: XCTestCase {
    func testIndependentProcessCannotAcquireUntilOwnerExits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = root.appendingPathComponent("lock")
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = ["-MFcntl=:flock", "-e", "open(my $f, '>>', $ARGV[0]) or die; flock($f, LOCK_EX) or die; print qq(ready\\n); $|=1; sleep 30", path.path]
        let output = Pipe()
        child.standardOutput = output
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        XCTAssertFalse(output.fileHandleForReading.availableData.isEmpty)
        XCTAssertThrowsError(try ProcessFileLock(at: path))
        child.terminate()
        child.waitUntilExit()
        let recovered = try ProcessFileLock(at: path)
        withExtendedLifetime(recovered) {}
    }

    func testSeparateStoresPreserveIndependentPreferencesAndRecents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("preferences.json")
        let a = ConfigurationStore(), b = ConfigurationStore()
        let baseline = GlobalPreferences.default
        var left = baseline, right = baseline
        left.markdown.mermaidEnabled = true
        left.recentProjectPaths = [root.appendingPathComponent("A")]
        right.markdown.mathEnabled = true
        right.recentProjectPaths = [root.appendingPathComponent("B")]
        let leftUpdate = left, rightUpdate = right
        async let first = a.mergeGlobalPreferences(updated: leftUpdate, baseline: baseline, at: url)
        async let second = b.mergeGlobalPreferences(updated: rightUpdate, baseline: baseline, at: url)
        _ = try await (first, second)
        let result = try await a.loadGlobalPreferences(at: url)
        XCTAssertTrue(result.markdown.mermaidEnabled)
        XCTAssertTrue(result.markdown.mathEnabled)
        XCTAssertEqual(Set(result.recentProjectPaths), Set(left.recentProjectPaths + right.recentProjectPaths))
    }
}
