extension LeonardoDocument {
    /// Constructs the response from the host's reserved source. The caller must
    /// independently confirm the reservation, source identity and resources.
    public func makeFormResponse(
        applying values: [String: LeonardoJSONValue]
    ) throws -> LeonardoDocument {
        guard isForm, metadata.document.signing == nil,
              !metadata.fields.values.contains(where: { $0.signerPosition != nil }),
              metadata.fields.values.contains(where: { !$0.readOnly }) else {
            throw LeonardoFormResponseError.ineligibleSource
        }
        guard let response = applyingFormValues(values) else {
            throw LeonardoFormResponseError.rejectedValues
        }
        let errors = LeonardoFormatParser.validate(response, context: .submission)
            .filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw LeonardoFormResponseError.invalidResponse(errors)
        }
        return response
    }
}

public enum LeonardoFormResponseError: Error, Sendable {
    case ineligibleSource
    case rejectedValues
    case invalidResponse([LeonardoDiagnostic])
}
