#if os(macOS)
import Foundation

/// Runs fixture Git commands without allowing either child output pipe to
/// fill while the test waits for process termination. The collectors keep
/// draining after their bounded prefix so a noisy failure cannot deadlock the
/// test runner.
enum DesktopGitProcessTestSupport {
    static func run(arguments: [String], at root: URL, input: Data? = nil) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        process.standardOutput = output
        process.standardError = errors
        if input == nil {
            process.standardInput = FileHandle.nullDevice
        } else {
            process.standardInput = Pipe()
        }

        let stdoutCollector = Collector(limit: 16 * 1_024 * 1_024)
        let stderrCollector = Collector(limit: 2 * 1_024 * 1_024)
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutCollector.drain(output.fileHandleForReading)
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrCollector.drain(errors.fileHandleForReading)
            readers.leave()
        }

        do {
            try process.run()
        } catch {
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
            readers.wait()
            throw error
        }
        if let input, let pipe = process.standardInput as? Pipe {
            pipe.fileHandleForWriting.write(input)
            try? pipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()
        readers.wait()

        let stdout = stdoutCollector.snapshot()
        let stderr = stderrCollector.snapshot()
        guard !stdout.overflow, !stderr.overflow else {
            throw NSError(domain: "DesktopGitProcessTestSupport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Git fixture output exceeded the test limit"])
        }
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "DesktopGitProcessTestSupport", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: stderr.data.isEmpty ? stdout.data : stderr.data,
                                                                        as: UTF8.self)])
        }
        return stdout.data
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var storage = Data()
        private var overflow = false

        init(limit: Int) { self.limit = limit }

        func drain(_ handle: FileHandle) {
            do {
                while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                    lock.lock()
                    if storage.count < limit {
                        let room = limit - storage.count
                        storage.append(chunk.prefix(room))
                        if chunk.count > room { overflow = true }
                    } else {
                        overflow = true
                    }
                    lock.unlock()
                }
            } catch {
                // The process termination and the test's exit status remain
                // authoritative; a closed pipe simply ends collection.
            }
        }

        func snapshot() -> (data: Data, overflow: Bool) {
            lock.lock(); defer { lock.unlock() }
            return (storage, overflow)
        }
    }
}
#endif
