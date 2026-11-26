import Foundation
import LeonardoDesktopSync

/// Owns one persistent browser renderer for all local preview registrations.
/// Preview documents are data submitted to that service; they never launch a
/// process of their own.
actor SyncPreviewWorker {
    private static let stopGracePeriod: TimeInterval = 1
    private static let stopPollInterval: TimeInterval = 0.05
    private let script: URL
    private var process: Process?
    private var input: FileHandle?

    init(bundle: URL) {
        script = bundle.appendingPathComponent("Contents/Resources/LeonardoPreview/scripts/preview_service.py")
    }

    func reconcile(enabled: Bool) throws {
        guard enabled else {
            stop()
            return
        }
        guard process?.isRunning != true else { return }
        stop()
        guard FileManager.default.isReadableFile(atPath: script.path) else {
            throw SyncHelperFailure("The bundled Leonardo preview helper is unavailable.")
        }

        let worker = Process()
        let pipe = Pipe()
        worker.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
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
