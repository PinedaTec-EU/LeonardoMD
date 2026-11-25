import AppKit
import LeonardoCore

extension AppSession {
    func showEmbeddedSignatures(_ signing: LeonardoEmbeddedSigning) async {
        guard let workspace = packageWorkspace else { return }
        let packageChanged = await Task.detached { workspace.hasSourceChanged() }.value
        guard packageWorkspace?.directoryURL == workspace.directoryURL else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("Certificate signatures in this document")
        if packageChanged || externalConflict {
            alert.informativeText = L10n.text("Signed document changed")
        } else {
            switch signing {
            case .invalidPackage:
                alert.informativeText = L10n.text("The document or its resources failed signature verification.")
            case .signatures(let signers):
                alert.informativeText = signers.map { signer in
                    var lines = [signer.position, embeddedSignatureStatus(signer.verification)]
                    if let subject = signer.certificateSubject, let fingerprint = signer.fingerprint {
                        lines += [L10n.format("Certificate subject: %@", subject), "SHA-256 \(fingerprint)"]
                    }
                    return lines.joined(separator: "\n")
                }.joined(separator: "\n\n")
            }
        }
        _ = await NativeDialog.present(alert, on: presentationWindow)
    }

    private func embeddedSignatureStatus(_ result: LeonardoSignatureVerification?) -> String {
        switch result {
        case .valid: return L10n.text("Signature valid · certificate trusted by macOS")
        case .untrustedCertificate: return L10n.text("Signing certificate not trusted")
        case .modifiedSnapshot: return L10n.text("Signed document changed")
        case .invalidSignature, .unknownCredential: return L10n.text("Signature verification failed")
        case nil: return L10n.text("No signature")
        }
    }
}
