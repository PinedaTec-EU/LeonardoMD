import AppKit
import LeonardoCore
import UniformTypeIdentifiers

@MainActor
enum CertificateSigningCopyReview {
    static func chooseCopy() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Verify certificate signing copy…")
        panel.allowedContentTypes = [.json]
        NativeDialog.present(panel) { url in
            Task {
                let result = await Task.detached { review(url) }.value
                let alert = NSAlert()
                alert.messageText = L10n.text("Certificate signing copy")
                switch result {
                case .positions(let positions):
                    alert.informativeText = positions.map { position in
                        var lines = [position.label, L10n.text(position.status)]
                        if let name = position.certificateName, let fingerprint = position.fingerprint {
                            lines += [name, "SHA-256 \(fingerprint)"]
                        }
                        return lines.joined(separator: "\n")
                    }.joined(separator: "\n\n")
                case .invalid:
                    alert.alertStyle = .warning
                    alert.informativeText = L10n.text("The signing copy is unreadable or its document or assets failed integrity checks.")
                case .otherMethod:
                    alert.informativeText = L10n.text("Choose a Leonardo copy that uses certificate signing.")
                }
                _ = await NativeDialog.present(alert)
            }
        }
    }

    private struct Position: Sendable {
        let label: String
        let status: String
        let certificateName: String?
        let fingerprint: String?
    }

    private enum Result: Sendable {
        case positions([Position])
        case invalid
        case otherMethod
    }

    private nonisolated static func review(_ url: URL) -> Result {
        do {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size <= LeonardoSigningExchange.maximumEnvelopeBytes else { return .invalid }
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let exchange = try LeonardoSigningExchange.decoded(data)
            guard exchange.session.declaration.method == .certificate else { return .otherMethod }
            let registry = try LeonardoSigningTrustRegistry(credentials: exchange.trustedCredentials)
            let results = exchange.session.signatureVerification(
                document: try exchange.document(), resources: try exchange.signingResources(),
                trustStore: registry
            )
            return .positions(exchange.session.declaration.positions.map { position in
                let status: String
                switch results[position.id] {
                case .valid: status = "Signature valid · certificate trusted by macOS"
                case .untrustedCertificate: status = "Signing certificate not trusted"
                case .modifiedSnapshot: status = "Signed document changed"
                case .invalidSignature, .unknownCredential: status = "Signature verification failed"
                case nil: status = "No signature"
                }
                let credential = exchange.session.positions[position.id]?.signature.flatMap {
                    registry.credential(id: $0.proof.credentialID)
                }
                return Position(label: position.label, status: status,
                                certificateName: credential.flatMap(LeonardoCertificateSignature.subject),
                                fingerprint: credential?.id)
            })
        } catch {
            return .invalid
        }
    }
}
