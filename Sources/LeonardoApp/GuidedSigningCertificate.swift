import AppKit
import LeonardoCore
import Security

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
                  let leaf = credential.certificateChain?.first,
                  let certificate = SecCertificateCreateWithData(nil, leaf as CFData),
                  let name = SecCertificateCopySubjectSummary(certificate) as String? else { return nil }
            return Self(identity: identity, credential: credential, name: name)
        }.sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    }
}
