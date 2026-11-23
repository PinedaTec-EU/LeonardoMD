#if os(macOS)
import Foundation

/// An independent TLS implementation observes response bytes and TLS shutdown.
/// The throwaway self-signed identity is local-only; production pinning is tested separately.
enum TLSClosureProbe {
    struct Result: Sendable {
        let response: Data
        let diagnostics: String
        let exitCode: Int32
        let timedOut: Bool
    }

    static func read(port: UInt16, fingerprint: Data, slowReader: Bool = false, readyFile: URL? = nil, holdOpenUntil: URL? = nil, sendSecondRequest: Bool = false) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try run(port: port, fingerprint: fingerprint, slowReader: slowReader, readyFile: readyFile, holdOpenUntil: holdOpenUntil, sendSecondRequest: sendSecondRequest)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    // Python's strict EOF mode distinguishes TLS close_notify from a TCP EOF.
    // The peer still checks the exact throwaway server certificate fingerprint.
    private static let pythonClient = #"""
import hashlib, socket, ssl, sys, time, pathlib
context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
context.check_hostname = False
context.verify_mode = ssl.CERT_NONE
slow = sys.argv[3] == "slow"
started = time.monotonic()
received = 0
reported = 0
raw = socket.socket()
raw.settimeout(10)
if slow:
    raw.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024)
raw.connect(("127.0.0.1", int(sys.argv[1])))
with raw:
    with context.wrap_socket(raw, server_hostname="localhost", suppress_ragged_eofs=False) as peer:
        if hashlib.sha256(peer.getpeercert(binary_form=True)).hexdigest() != sys.argv[2]:
            raise RuntimeError("Fixture certificate pin mismatch")
        peer.sendall(b"GET /v1/snapshot HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        extra = sys.argv[6] == "extra"
        while True:
            data = peer.recv(1024 if slow else 4096)
            if not data:
                print("TLS_CLOSE_NOTIFY bytes=%d elapsed=%.3f" % (received, time.monotonic() - started), file=sys.stderr)
                if sys.argv[4]:
                    pathlib.Path(sys.argv[4]).write_text("ready")
                until = time.monotonic() + 40
                while sys.argv[5] and not pathlib.Path(sys.argv[5]).exists() and time.monotonic() < until:
                    time.sleep(0.02)
                break
            if extra:
                try:
                    peer.sendall(b"GET /v1/second HTTP/1.1\r\nHost: localhost\r\n\r\n")
                except ssl.SSLError:
                    pass
                extra = False
            received += len(data)
            if received - reported >= 262144:
                print("TLS_PROGRESS bytes=%d elapsed=%.3f" % (received, time.monotonic() - started), file=sys.stderr, flush=True)
                reported = received
            sys.stdout.buffer.write(data)
            sys.stdout.buffer.flush()
            if slow:
                time.sleep(0.002)
"""#

    private static func run(port: UInt16, fingerprint: Data, slowReader: Bool, readyFile: URL?, holdOpenUntil: URL?, sendSecondRequest: Bool) throws -> Result {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let output = root.appendingPathComponent("response")
        let errors = root.appendingPathComponent("diagnostics")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: output)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer { try? outputHandle.close(); try? errorHandle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", pythonClient, String(port), fingerprint.map { String(format: "%02x", $0) }.joined(), slowReader ? "slow" : "normal", readyFile?.path ?? "", holdOpenUntil?.path ?? "", sendSecondRequest ? "extra" : "single"]
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        // CI exhausted 30 seconds while bytes were still arriving; allow a bounded
        // diagnostic run without changing the receive window or byte assertions.
        // This harness deadline stays below the server's 120-second operation cap.
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        let timedOut = process.isRunning
        if timedOut { process.terminate() }
        process.waitUntilExit()
        return Result(response: try Data(contentsOf: output),
                      diagnostics: try String(contentsOf: errors, encoding: .utf8),
                      exitCode: process.terminationStatus, timedOut: timedOut)
    }
}
#endif
