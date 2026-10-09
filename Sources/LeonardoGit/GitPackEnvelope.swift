import Foundation
import CryptoKit

/// Shared validation for a wire pack and its durable, bounded archive.
enum GitPackEnvelope {
    static func objectCount(in pack: Data, sha256: Bool, maximumBytes: Int, maximumObjects: UInt32) throws -> UInt32 {
        let checksumSize = sha256 ? 32 : 20
        guard maximumBytes >= 0, pack.count <= maximumBytes else { throw GitWireError.responseTooLarge }
        guard pack.startIndex == 0, pack.count >= 12 + checksumSize, pack.starts(with: Data("PACK".utf8)) else { throw GitWireError.invalidPack }
        let version = pack[4..<8].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let count = pack[8..<12].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard [2, 3].contains(version), count <= maximumObjects else { throw GitWireError.invalidPack }
        let body = pack.dropLast(checksumSize)
        let checksum = sha256 ? Data(SHA256.hash(data: body)) : Data(Insecure.SHA1.hash(data: body))
        guard pack.suffix(checksumSize) == checksum else { throw GitWireError.invalidPack }
        return count
    }
}
