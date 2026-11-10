import Foundation

/// Safe, bounded context for a failed HTTPS response stream.
public struct HTTPSFailureDiagnostics: Equatable, Sendable {
    public enum Operation: String, Sendable {
        case status
        case snapshot
        case catalogue
        case file
        case other

        init(path: String) {
            if path.hasSuffix("/status") { self = .status }
            else if path.hasSuffix("/snapshot") { self = .snapshot }
            else if path.hasSuffix("/catalogue") { self = .catalogue }
            else if path.hasSuffix("/file") { self = .file }
            else { self = .other }
        }
    }

    private static let userInfoKey = "eu.pinedatec.LeonardoSyncTransport.HTTPSFailureDiagnostics"

    public let operation: Operation
    public let errorDomain: String
    public let errorCode: Int
    public let httpStatusCode: Int?
    public let receivedBodyBytes: Int
    public let expectedBodyBytes: Int64?

    /// A compact, shareable code containing no endpoint, credentials, identifiers or response data.
    public var compactCode: String {
        let status = httpStatusCode.map(String.init) ?? "?"
        let expected = expectedBodyBytes.map(String.init) ?? "?"
        return "[LL1 op=\(operation.rawValue) domain=\(errorDomain) code=\(errorCode) http=\(status) bytes=\(receivedBodyBytes)/\(expected)]"
    }

    public static func from(_ error: Error) -> HTTPSFailureDiagnostics? {
        (error as NSError).userInfo[userInfoKey] as? HTTPSFailureDiagnostics
    }

    static func annotate(_ error: Error, operation: Operation, httpStatusCode: Int?,
                         receivedBodyBytes: Int, expectedBodyBytes: Int64?) -> Error {
        guard let urlError = error as? URLError,
              urlError.code != .cancelled,
              (error as NSError).domain == NSURLErrorDomain else {
            return error
        }

        let diagnostics = HTTPSFailureDiagnostics(
            operation: operation,
            errorDomain: NSURLErrorDomain,
            errorCode: urlError.code.rawValue,
            httpStatusCode: httpStatusCode,
            receivedBodyBytes: receivedBodyBytes,
            expectedBodyBytes: expectedBodyBytes)
        var userInfo = (error as NSError).userInfo
        userInfo[userInfoKey] = diagnostics
        userInfo[NSLocalizedDescriptionKey] = "\(URLError(urlError.code).localizedDescription)\n\(diagnostics.compactCode)"
        return URLError(urlError.code, userInfo: userInfo)
    }
}
