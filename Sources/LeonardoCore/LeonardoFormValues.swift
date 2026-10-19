import Foundation

extension LeonardoDocument {
    /// Applies an atomic form-only mutation. Lifecycle and document identity are
    /// enforced by the caller; definitions/body are never changed here.
    public func applyingFormValues(_ changes: [String: LeonardoJSONValue]) -> LeonardoDocument? {
        guard isForm else { return nil }
        for (fieldID, value) in changes {
            guard let field = metadata.fields[fieldID], !field.readOnly else { return nil }
            switch (field.type, value) {
            case (.checkbox, .boolean), (.number, .null): break
            case (.number, .number(let number)):
                guard number.isFinite else { return nil }
            case (.checkbox, _): return nil
            case (_, .string): break // Incomplete/invalid scalar drafts are retained.
            default: return nil
            }
        }
        var result = self
        for (fieldID, value) in changes { result.metadata.values[fieldID] = value }
        return result
    }
}
