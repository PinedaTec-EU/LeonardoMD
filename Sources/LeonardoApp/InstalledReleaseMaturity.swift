import CryptoKit
import Foundation
import Observation
import OSLog

/// An authenticated publication assertion, independent of the update subscription.
struct ReleaseMaturityProof: Codable, Sendable {
    struct Publication: Codable, Equatable, Sendable {
        let schema: Int
        let repository: String
        let version: String
        let build: String
        let executableSHA256: String
        let archiveSHA256: String
        let channel: String
    }
    let payload: Data
    let signature: Data

    func verifies(identity: InstalledReleaseIdentity, publicKey: Data) -> Bool {
        guard payload.count <= 4096, signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              key.isValidSignature(signature, for: payload),
              let publication = try? JSONDecoder().decode(Publication.self, from: payload) else { return false }
        return publication.schema == 1 && publication.repository == "PinedaTec-EU/LeonardoMD"
            && publication.channel == "stable" && publication.version == identity.version
            && publication.build == identity.build && publication.executableSHA256 == identity.executableSHA256
            && publication.archiveSHA256.count == 64
            && publication.archiveSHA256.allSatisfy { "0123456789abcdef".contains($0) }
    }
}

struct InstalledReleaseIdentity: Sendable {
    let version: String
    let build: String
    let executableSHA256: String

    static func read(configuration: UpdateConfiguration, executable: URL?) throws -> Self {
        guard let version = configuration.version.version, let build = configuration.version.build,
              version.split(separator: ".").count == 3,
              version.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
              !build.isEmpty, build.allSatisfy({ $0.isASCII && $0.isNumber }), let executable else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let file = try FileHandle(forReadingFrom: executable)
        defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        return Self(version: version, build: build,
                    executableSHA256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}

/// The fixed HTTPS endpoint and the signature are independent trust boundaries.
enum ReleaseMaturityTransport {
    static func fetch(version: String) async throws -> Data {
        let url = URL(string: "https://github.com/PinedaTec-EU/LeonardoMD/releases/download/v\(version)/release-maturity.json")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.expectedContentLength <= 16_384 else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 16_384 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}

@MainActor @Observable
final class InstalledReleaseMaturity {
    static let cacheKey = "verifiedInstalledReleaseMaturity"
    private(set) var channel: UpdateChannel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let publicKey: Data?
    @ObservationIgnored private let identify: @Sendable () async throws -> InstalledReleaseIdentity
    @ObservationIgnored private let fetch: @Sendable (String) async throws -> Data
    @ObservationIgnored private var inProgress = false
    @ObservationIgnored private let enabled: Bool
    @ObservationIgnored private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "release-maturity")

    init(configuration: UpdateConfiguration, defaults: UserDefaults = .standard,
         identify: (@Sendable () async throws -> InstalledReleaseIdentity)? = nil,
         fetch: @escaping @Sendable (String) async throws -> Data = ReleaseMaturityTransport.fetch) {
        self.defaults = defaults
        channel = configuration.installedChannel
        publicKey = configuration.publicKey
        enabled = configuration.isConfigured && channel == .beta
        let executable = Bundle.main.executableURL
        self.identify = identify ?? {
            try await Task.detached { try InstalledReleaseIdentity.read(configuration: configuration, executable: executable) }.value
        }
        self.fetch = fetch
    }

    func refresh() async {
        guard enabled, channel != .stable, !inProgress, let publicKey else { return }
        inProgress = true
        defer { inProgress = false }
        do {
            let identity = try await identify()
            if let cached = defaults.data(forKey: Self.cacheKey), accepts(cached, identity: identity, key: publicKey) {
                channel = .stable
                logger.info("release_maturity_verified source=cache")
                return
            }
            let downloaded = try await fetch(identity.version)
            guard accepts(downloaded, identity: identity, key: publicKey) else {
                logger.error("release_maturity_rejected reason=invalid_proof")
                return
            }
            defaults.set(downloaded, forKey: Self.cacheKey)
            channel = .stable
            logger.info("release_maturity_verified source=publication")
        } catch {
            logger.info("release_maturity_unavailable")
        }
    }

    private func accepts(_ data: Data, identity: InstalledReleaseIdentity, key: Data) -> Bool {
        guard data.count <= 16_384, let proof = try? JSONDecoder().decode(ReleaseMaturityProof.self, from: data) else { return false }
        return proof.verifies(identity: identity, publicKey: key)
    }
}
