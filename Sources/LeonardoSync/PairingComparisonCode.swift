import Foundation
import CryptoKit

/// Both peers calculate the display code locally. A relayed challenge under another TLS
/// certificate produces a different code, even if an intermediary copies the server response.
public enum PairingComparisonCode {
    public static func make(serverFingerprint: Data, credential: String, requestID: UUID, kind: PairingClientKind = .readOnly) throws -> String {
        guard serverFingerprint.count == 32, credential.count == 64, credential.allSatisfy(\.isHexDigit) else {
            throw PairingError.invalidCredential
        }
        var transcript = Data("LittleLeonardo-pair-v1".utf8)
        transcript.append(serverFingerprint)
        transcript.append(contentsOf: SHA256.hash(data: Data(credential.utf8)))
        transcript.append(Data(requestID.uuidString.utf8))
        if kind == .desktopPeer { transcript.append(Data("desktop-peer-proposals-v1".utf8)) }
        let bytes = SHA256.hash(data: transcript).prefix(4)
        let number = bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 100_000_000
        return String(format: "%08u", number)
    }
}
