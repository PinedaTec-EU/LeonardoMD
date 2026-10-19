import Foundation

/// Enforces MDLF rules that JSON Schema cannot express without coupling the
/// schema to implementation-specific policy. It deliberately validates only
/// definitions and layout. Filled values may be invalid while a draft is
/// being edited and must remain serializable for later correction.
enum LeonardoFormatMetadataSafety {
    static func validate(_ metadata: LeonardoMetadata) throws {
        let document = LeonardoDocument(body: "", metadata: metadata)
        let diagnostics = LeonardoFormatValidator.validate(document, context: .draft)
        let unsafe = diagnostics.contains { diagnostic in
            guard diagnostic.severity == .error else { return false }
            return !diagnostic.code.hasPrefix("value.")
                && !diagnostic.code.hasPrefix("body.")
        }
        if unsafe {
            throw LeonardoFormatError.invalidMetadataJSON
        }
    }
}
