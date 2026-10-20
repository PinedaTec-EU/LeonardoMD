import AppKit
import SwiftUI
import CryptoKit
import XCTest
@testable import LeonardoApp

@MainActor
final class InstalledReleaseMaturityTests: XCTestCase {
    let identity = InstalledReleaseIdentity(version: "0.1.601", build: "601", executableSHA256: String(repeating: "a", count: 64))

    func configuration(key: Curve25519.Signing.PrivateKey, channel: UpdateChannel = .beta) -> UpdateConfiguration {
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        return UpdateConfiguration(info: ["CFBundleShortVersionString": identity.version, "CFBundleVersion": identity.build,
            "LeonardoUpdateChannel": channel.rawValue, "SUPublicEDKey": publicKey, "LeonardoUpdatePublicKey": publicKey,
            "LeonardoStableFeedURL": "https://example.com/stable.xml", "LeonardoBetaFeedURL": "https://example.com/beta.xml"])
    }

    func proof(key: Curve25519.Signing.PrivateKey, version: String = "0.1.601", build: String = "601",
               digest: String = String(repeating: "a", count: 64), channel: String = "stable") throws -> Data {
        let payload = try JSONEncoder().encode(ReleaseMaturityProof.Publication(schema: 1,
            repository: "PinedaTec-EU/LeonardoMD", version: version, build: build, executableSHA256: digest,
            archiveSHA256: String(repeating: "b", count: 64), channel: channel))
        return try JSONEncoder().encode(ReleaseMaturityProof(payload: payload, signature: key.signature(for: payload)))
    }

    func testRealSparkleKeychainSignatureIsCompatibleWithRuntimeVerifier() throws {
        // Public assertion generated locally from the published stable ZIP; no private key fixture.
        let proof = try JSONDecoder().decode(ReleaseMaturityProof.self, from: SparkleMaturityFixture.data)
        let publication = try JSONDecoder().decode(ReleaseMaturityProof.Publication.self, from: proof.payload)
        XCTAssertEqual(publication.archiveSHA256, "24f7689973b8cb19473a81fba919bf9593136dcce1980a828245d32f9b77e8b6")
        let identity = InstalledReleaseIdentity(version: "0.1.571", build: "571", executableSHA256: publication.executableSHA256)
        XCTAssertTrue(proof.verifies(identity: identity, publicKey: Data(base64Encoded: "a3GPslwOW8arEKunqgwyZDTsngVAFY8jLjQiR1bzyxI=")!))
    }

    func testCapturePromotedPreferences() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["LEONARDO_MATURITY_EVIDENCE"]
            ?? environment["LEONARDO_VISUAL_EVIDENCE"].map({ $0 + "/maturity" }) else {
            throw XCTSkip("Set LEONARDO_MATURITY_EVIDENCE for native promotion captures")
        }
        let destination = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let head = environment["EVIDENCE_SHA"] ?? "local working tree"
        try "Head: \(head)\nSurface: native NSHostingView Updates preferences\nViewport: 580x620 points\nStates: beta and authenticated stable, subscriptions stable and beta, languages en/es\nFixture: synthetic 0.1.601 with ephemeral Ed25519 key; no install/network/fresh-process claim\n".write(
            to: destination.appendingPathComponent("provenance.txt"), atomically: true, encoding: .utf8)
        let previous = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previous }
        let key = Curve25519.Signing.PrivateKey()
        let config = configuration(key: key)
        let identity = self.identity
        let data = try proof(key: key)
        for subscription in UpdateChannel.allCases {
            let suite = "ReleaseMaturityCapture.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(subscription.rawValue, forKey: ApplicationUpdates.channelPreferenceKey)
            let maturity = InstalledReleaseMaturity(configuration: config, defaults: defaults,
                identify: { identity }, fetch: { _ in data })
            let updates = ApplicationUpdates(defaults: defaults, configuration: config, driver: FakeUpdateDriver(), maturity: maturity)
            for promoted in [false, true] {
                if promoted { await maturity.refresh() }
                for language in AppLanguage.allCases {
                    LanguageSettings.shared.language = language
                    let host = NSHostingView(rootView: UpdatePreferencesView(updates: updates)
                        .buttonStyle(PremiumButtonStyle()).frame(width: 580, height: 620)
                        .background(Color(nsColor: .windowBackgroundColor)))
                    let filename = "maturity-\(language.rawValue)-\(subscription.rawValue)-\(promoted ? "promoted" : "beta").png"
                    try await NativeViewCaptureSupport.capture(host, size: NSSize(width: 580, height: 620),
                        to: destination.appendingPathComponent(filename), settlingMilliseconds: 250,
                        title: "Leonardo Installed Maturity QA")
                }
            }
        }
    }

    func testPromotionPreservesBothSubscriptionsAndSurvivesOfflineRelaunch() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = try proof(key: key)
        let config = configuration(key: key)
        let identity = self.identity
        for subscription in UpdateChannel.allCases {
            let suite = "ReleaseMaturityTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(subscription.rawValue, forKey: ApplicationUpdates.channelPreferenceKey)
            let maturity = InstalledReleaseMaturity(configuration: config, defaults: defaults,
                identify: { identity }, fetch: { _ in data })
            let updates = ApplicationUpdates(defaults: defaults, configuration: config, driver: FakeUpdateDriver(), maturity: maturity)
            XCTAssertEqual(updates.installedChannel, .beta)
            await maturity.refresh()
            XCTAssertEqual(updates.installedChannel, .stable)
            XCTAssertEqual(updates.channel, subscription)
            XCTAssertEqual(defaults.string(forKey: ApplicationUpdates.channelPreferenceKey), subscription.rawValue)
            XCTAssertEqual(config.installedChannel, .beta)
            let offline = InstalledReleaseMaturity(configuration: config, defaults: defaults,
                identify: { identity }, fetch: { _ in throw URLError(.notConnectedToInternet) })
            await offline.refresh()
            XCTAssertEqual(offline.channel, .stable)
        }
    }

    func testRejectsWrongKeyIdentityChannelAndTamperedPayload() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let config = configuration(key: key)
        let identity = self.identity
        let valid = try proof(key: key)
        let decoded = try JSONDecoder().decode(ReleaseMaturityProof.self, from: valid)
        let tampered = try JSONEncoder().encode(ReleaseMaturityProof(payload: decoded.payload + Data([32]), signature: decoded.signature))
        let cases = try [proof(key: Curve25519.Signing.PrivateKey()), proof(key: key, version: "0.1.600"),
            proof(key: key, build: "600"), proof(key: key, digest: String(repeating: "c", count: 64)),
            proof(key: key, channel: "beta"), tampered, Data("{}".utf8), Data(repeating: 0, count: 16_385)]
        for data in cases {
            let suite = "ReleaseMaturityTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let maturity = InstalledReleaseMaturity(configuration: config, defaults: defaults,
                identify: { identity }, fetch: { _ in data })
            await maturity.refresh()
            XCTAssertEqual(maturity.channel, .beta)
            XCTAssertNil(defaults.data(forKey: InstalledReleaseMaturity.cacheKey))
        }
    }

    func testCachedPromotionDoesNotApplyToLaterBetaAndNetworkFailureKeepsBeta() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let config = configuration(key: key)
        let identity = self.identity
        let suite = "ReleaseMaturityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try proof(key: key, version: "0.1.600", build: "600"), forKey: InstalledReleaseMaturity.cacheKey)
        let maturity = InstalledReleaseMaturity(configuration: config, defaults: defaults,
            identify: { identity }, fetch: { _ in throw URLError(.notConnectedToInternet) })
        await maturity.refresh()
        XCTAssertEqual(maturity.channel, .beta)
    }
}
