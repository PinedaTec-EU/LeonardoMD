import Foundation

/// Status comes from the archive bytes, independent of any local signing session.
public enum LeonardoEmbeddedSigning: Sendable {
    public struct Signer: Sendable {
        public let position: String
        public let certificateSubject: String?
        public let fingerprint: String?
        public let verification: LeonardoSignatureVerification?
    }

    case invalidPackage
    case signatures([Signer])

    static let entryName = "META-INF/leonardo-signatures.json"

    public static func archive(_ exchange: LeonardoSigningExchange, documentName: String) throws -> Data {
        let document = LeonardoZIPArchive.Entry(name: documentName, data: Data(exchange.source.utf8))
        let assets = try assetEntries(exchange.resources)
        let signatures = try LeonardoZIPArchive.Entry(name: entryName, data: LeonardoSigningExchange.encoded(exchange))
        let entries = [document, signatures] + assets
        guard ["mdlf", "mdlr"].contains((documentName as NSString).pathExtension.lowercased()),
              !documentName.contains("/"), case .signatures = read(entries: entries, document: document) else {
            throw LeonardoSigningError.integrityFailure
        }
        return try LeonardoZIPArchive.write(entries)
    }

    private static func assetEntries(_ resources: [LeonardoSigningExchangeResource]) throws -> [LeonardoZIPArchive.Entry] {
        var assets: [String: Data] = [:]
        for resource in resources {
            guard let path = LeonardoLocalImagePolicy.portableSigningImagePath(resource.reference),
                  path.hasPrefix("assets/") else {
                throw LeonardoSigningError.invalidResourceReference(resource.reference)
            }
            if let previous = assets.updateValue(resource.bytes, forKey: path), previous != resource.bytes {
                throw LeonardoSigningError.integrityFailure
            }
        }
        return assets.keys.sorted().compactMap { name in
            assets[name].map { LeonardoZIPArchive.Entry(name: name, data: $0) }
        }
    }

    static func read(entries: [LeonardoZIPArchive.Entry], document: LeonardoZIPArchive.Entry) -> Self? {
        guard let signatures = entries.first(where: { $0.name == entryName }) else { return nil }
        do {
            let exchange = try LeonardoSigningExchange.decoded(signatures.data)
            guard exchange.session.declaration.method == .certificate,
                  !exchange.session.completionOrder.isEmpty,
                  document.data == Data(exchange.source.utf8) else { return .invalidPackage }
            let assets = entries.filter { $0.name != entryName && $0.name != document.name }
            let expected = try assetEntries(exchange.resources)
            guard assets.count == expected.count,
                  zip(assets.sorted(by: { $0.name < $1.name }), expected).allSatisfy({
                      $0.name == $1.name && $0.data == $1.data
                  }) else { return .invalidPackage }
            let resources = exchange.resources.map(\.signingResource)
            let registry = try LeonardoSigningTrustRegistry(credentials: exchange.trustedCredentials)
            let verification = exchange.session.signatureVerification(
                document: try exchange.document(), resources: resources, trustStore: registry
            )
            return .signatures(exchange.session.declaration.positions.map { position in
                let proof = exchange.session.positions[position.id]?.signature?.proof
                let credential = proof.flatMap { registry.credential(id: $0.credentialID) }
                return Signer(position: position.label,
                              certificateSubject: credential.flatMap(LeonardoCertificateSignature.subject),
                              fingerprint: credential?.id,
                              verification: verification[position.id])
            })
        } catch {
            return .invalidPackage
        }
    }
}
