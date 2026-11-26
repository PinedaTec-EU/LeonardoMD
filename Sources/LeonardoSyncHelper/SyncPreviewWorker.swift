import Foundation
import LeonardoDesktopSync

/// Owns one persistent browser renderer for all local preview registrations.
/// Preview documents are data submitted to that service; they never launch a
/// process of their own.
actor SyncPreviewWorker {
    private static let stopGracePeriod: TimeInterval = 1
    private static let stopPollInterval: TimeInterval = 0.05
    private static let minimumPythonMajor = 3
    private static let minimumPythonMinor = 9
    private static let pythonCandidates = [
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/opt/local/bin/python3",
        "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
    ]
    private let script: URL
    private var process: Process?
    private var input: FileHandle?
    private var interpreterChecked = false
    private var interpreter: URL?

    init(bundle: URL) {
        script = bundle.appendingPathComponent("Contents/Resources/LeonardoPreview/scripts/preview_service.py")
    }

    /// Returns whether the optional preview service is running. Missing Python
    /// is an ordinary unavailable-preview state, not a Sync failure.
    func reconcile(enabled: Bool) throws -> Bool {
        guard enabled else {
            stop()
            return false
        }
        guard process?.isRunning != true else { return true }
        stop()
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            throw SyncHelperFailure("The bundled Leonardo preview helper is unavailable.")
        }
        if !interpreterChecked {
            interpreter = Self.findSupportedPython()
            interpreterChecked = true
        }
        guard let interpreter else { return false }

        let worker = Process()
        let pipe = Pipe()
        worker.executableURL = interpreter
        worker.arguments = [
            "-I", "-B", "-c",
            "import runpy, sys; sys.path.insert(0, sys.argv[1]); runpy.run_path(sys.argv[2], run_name='__main__')",
            script.deletingLastPathComponent().path, script.path
        ]
        worker.standardInput = pipe
        worker.standardOutput = FileHandle.nullDevice
        worker.standardError = FileHandle.nullDevice
        try worker.run()
        process = worker
        input = pipe.fileHandleForWriting
        return true
    }

    private static func findSupportedPython() -> URL? {
        for path in pythonCandidates {
            let candidate = URL(fileURLWithPath: path)
            guard FileManager.default.isExecutableFile(atPath: candidate.path) else { continue }
            let resolved = candidate.resolvingSymlinksInPath()
            // macOS may expose /usr/bin/python3 as a CLT installer shim. Never
            // execute it: doing so can prompt for installation on every pass.
            guard resolved.path != "/usr/bin/python3" else { continue }
            guard isSupportedPython(at: resolved) else { continue }
            return resolved
        }
        return nil
    }

    private static func isSupportedPython(at executable: URL) -> Bool {
        let output = Pipe()
        let probe = Process()
        probe.executableURL = executable
        probe.arguments = [
            "-I", "-B", "-c",
            "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}', end='')",
        ]
        probe.standardOutput = output
        probe.standardError = FileHandle.nullDevice
        do {
            try probe.run()
            probe.waitUntilExit()
        } catch {
            return false
        }
        guard probe.terminationStatus == 0,
              let value = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            return false
        }
        let components = value.split(separator: ".", omittingEmptySubsequences: true)
        guard components.count == 2,
              let major = Int(components[0]),
              let minor = Int(components[1]) else {
            return false
        }
        return major > minimumPythonMajor ||
            (major == minimumPythonMajor && minor >= minimumPythonMinor)
    }

    private func stop() {
        let current = process
        process = nil
        try? input?.close()
        input = nil
        guard let current else { return }
        if current.isRunning {
            let deadline = Date().addingTimeInterval(Self.stopGracePeriod)
            while current.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: Self.stopPollInterval)
            }
            if current.isRunning { current.terminate() }
        }
        current.waitUntilExit()
    }
}
