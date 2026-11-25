import AppKit
import LeonardoCore
import Security
import SwiftUI

struct GuidedSigningCertificate: Identifiable {
    let identity: SecIdentity
    let credential: LeonardoSigningCredential
    let name: String

    var id: String { credential.id }

    static func available() -> [Self] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let identities = result as? [SecIdentity] else { return [] }
        var seen = Set<String>()
        return identities.compactMap { identity in
            guard let credential = try? LeonardoCertificateSignature.credential(using: identity),
                  seen.insert(credential.id).inserted,
                  let name = LeonardoCertificateSignature.subject(of: credential) else { return nil }
            return Self(identity: identity, credential: credential, name: name)
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}

extension GuidedSigningCertificate {
    @MainActor
    static func authorizeSigning(positionID: String, session: AppSession) async {
        guard let current = session.guidedSigningSession,
              let assignment = current.positions[positionID]?.assignment else { return }
        guard let chosen = available().first(where: { $0.id == assignment.credentialID }) else {
            session.guidedSigningActionProblem = L10n.text("The assigned signing certificate is unavailable or untrusted.")
            return
        }
        let alert = NSAlert()
        alert.messageText = L10n.text("Sign this Leonardo revision with a certificate?")
        alert.informativeText = "\(chosen.name)\nSHA-256 \(chosen.id)"
        alert.addButton(withTitle: L10n.text("Sign"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        guard await NativeDialog.present(alert, on: session.presentationWindow) == .alertFirstButtonReturn,
              session.guidedSigningSession == current else { return }
        await session.signGuidedPosition(positionID: positionID, password: "", certificate: chosen)
    }
}

struct GuidedSigningCertificatePicker: View {
    @Binding var selection: GuidedSigningCertificate?
    @State private var certificates: [GuidedSigningCertificate] = []
    @State private var loaded = false

    var body: some View {
        Picker(L10n.text("Signing certificate"), selection: Binding(
            get: { selection?.id ?? "" },
            set: { id in selection = certificates.first { $0.id == id } }
        )) {
            Text(L10n.text("Choose a certificate")).tag("")
            ForEach(certificates) { certificate in
                Text("\(certificate.name) · \(certificate.id.suffix(12))").tag(certificate.id)
            }
        }
        Button(L10n.text("Load Keychain certificates")) {
            certificates = GuidedSigningCertificate.available()
            selection = certificates.first { $0.id == selection?.id }
            loaded = true
        }
        if loaded && certificates.isEmpty {
            Text(L10n.text("No eligible certificates found in Keychain."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
