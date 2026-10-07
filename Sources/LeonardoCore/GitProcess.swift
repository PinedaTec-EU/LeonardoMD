import Foundation

struct GitCommandResult: Sendable {
    let arguments: [String]
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var message: String {
        let output = [stderr, stdout]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GitProcessRunner: Sendable {
    let executableURL: URL
    let environment: [String: String]

    init(executableURL: URL) {
        self.executableURL = executableURL
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        environment["LANG"] = "C"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        self.environment = environment
    }

    func run(arguments: [String], at rootURL: URL) async throws -> GitCommandResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCollector = OutputCollector()
        let stderrCollector = OutputCollector()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = rootURL
        process.environment = environment
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let readers = DispatchGroup()
        // One reader owns each stream through EOF. Process exit alone does not
        // mean an in-flight readability callback has appended its final bytes.
        DispatchQueue.global(qos: .utility).async(group: readers) {
            stdoutCollector.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        }
        DispatchQueue.global(qos: .utility).async(group: readers) {
            stderrCollector.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                readers.notify(queue: .global(qos: .utility)) {
                    let result = GitCommandResult(
                        arguments: arguments,
                        exitCode: process.terminationStatus,
                        stdout: String(data: stdoutCollector.data, encoding: .utf8) ?? "",
                        stderr: String(data: stderrCollector.data, encoding: .utf8) ?? ""
                    )
                    continuation.resume(returning: result)
                }
            }
            do {
                try process.run()
            } catch {
                try? stdoutPipe.fileHandleForWriting.close()
                try? stderrPipe.fileHandleForWriting.close()
                continuation.resume(throwing: error)
            }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }
}
