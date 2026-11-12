#if os(macOS)
import Foundation
import LeonardoSyncTransport

struct DesktopCertificateGenerator: Sendable {
    func generate(password: String) async throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let passwordURL = root.appendingPathComponent("password")
        try Data(password.utf8).write(to: passwordURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordURL.path)
        let key = root.appendingPathComponent("key.pem")
        let certificate = root.appendingPathComponent("certificate.pem")
        let archive = root.appendingPathComponent("identity.p12")
        try await run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650",
                       "-subj", "/CN=LeonardoMD local synchronization", "-keyout", key.path, "-out", certificate.path])
        try await run(["pkcs12", "-export", "-inkey", key.path, "-in", certificate.path,
                       "-out", archive.path, "-passout", "file:" + passwordURL.path])
        return try Data(contentsOf: archive)
    }

    private func run(_ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let status = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
            process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
            do { try process.run() }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw TransportError.invalidIdentity }
    }
}
#endif
