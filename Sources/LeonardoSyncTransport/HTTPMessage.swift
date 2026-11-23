import Foundation

public enum TransportError: Error, Equatable, Sendable {
    case malformedRequest, requestTooLarge, responseTooLarge, connectionClosed, invalidEndpoint, invalidIdentity, unexpectedResponse
}

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public init(status: Int, body: Data = Data()) { self.status = status; self.body = body }

    func encoded() -> Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized",
                      403: "Forbidden", 404: "Not Found", 409: "Conflict", 413: "Content Too Large",
                      500: "Internal Server Error", 503: "Service Unavailable"][status] ?? "Error"
        var data = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".utf8)
        data.append(body)
        return data
    }
}

/// One bounded HTTP/1.1 request per TLS connection; no chunking or pipelining.
struct HTTPRequestParser {
    private(set) var bytes = Data()
    static let maximumHeaderBytes = 8 * 1_024
    static let maximumBodyBytes = 32 * 1_024

    mutating func append(_ data: Data) throws -> HTTPRequest? {
        guard data.count <= Self.maximumHeaderBytes + Self.maximumBodyBytes - bytes.count else {
            throw TransportError.requestTooLarge
        }
        bytes.append(data)
        guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
            guard bytes.count <= Self.maximumHeaderBytes else { throw TransportError.requestTooLarge }
            return nil
        }
        guard boundary.lowerBound <= Self.maximumHeaderBytes,
              let head = String(data: bytes[..<boundary.lowerBound], encoding: .utf8) else {
            throw TransportError.malformedRequest
        }
        let lines = head.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: false)
        guard first.count == 3, ["GET", "POST"].contains(String(first[0])), first[2] == "HTTP/1.1",
              first[1].hasPrefix("/"), !first[1].contains("#") else { throw TransportError.malformedRequest }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else {
                throw TransportError.malformedRequest
            }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  headers[name] == nil else { throw TransportError.malformedRequest }
            headers[name] = value
        }
        let lengthText = headers["content-length"] ?? "0"
        guard headers["host"] != nil, headers["transfer-encoding"] == nil,
              !lengthText.isEmpty, lengthText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let length = Int(lengthText), length >= 0,
              length <= Self.maximumBodyBytes else { throw TransportError.malformedRequest }
        let expected = boundary.upperBound + length
        guard bytes.count >= expected else { return nil }
        guard bytes.count == expected else { throw TransportError.malformedRequest }
        return HTTPRequest(method: String(first[0]), path: String(first[1]), headers: headers,
                           body: Data(bytes[boundary.upperBound..<expected]))
    }
}
