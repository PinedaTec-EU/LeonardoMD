import Foundation
import CryptoKit

/// Writes complete objects, so receiving servers need no thin-pack base reconstruction.
public enum GitPackWriter {
    public static func encode(objects: [GitObject], sha256: Bool = false,
                              maximumBytes: Int = 256 * 1_024 * 1_024,
                              maximumObjectBytes: Int = GitPack.Limits().objectBytes) throws -> Data {
        guard objects.count <= 100_000, maximumObjectBytes >= 0, maximumBytes >= 12 + (sha256 ? 32 : 20) else { throw GitWireError.responseTooLarge }
        var ids: Set<String> = []
        var unique: [GitObject] = []
        for object in objects {
            guard object.data.count <= maximumObjectBytes else { throw GitWireError.responseTooLarge }
            guard GitObject.create(kind: object.kind, data: object.data, sha256: sha256).id == object.id else {
                throw GitWireError.invalidObjectID
            }
            if ids.insert(object.id).inserted { unique.append(object) }
        }
        let count = UInt32(unique.count)
        var pack = Data([80, 65, 67, 75, 0, 0, 0, 2,
                         UInt8(truncatingIfNeeded: count >> 24), UInt8(truncatingIfNeeded: count >> 16),
                         UInt8(truncatingIfNeeded: count >> 8), UInt8(truncatingIfNeeded: count)])
        for object in unique {
            let type: UInt8
            switch object.kind {
            case .commit: type = 1
            case .tree: type = 2
            case .blob: type = 3
            case .tag: type = 4
            }
            var size = object.data.count
            var header = Data()
            var byte = (type << 4) | UInt8(size & 15)
            size >>= 4
            if size > 0 { byte |= 128 }
            header.append(byte)
            while size > 0 {
                byte = UInt8(size & 127); size >>= 7
                if size > 0 { byte |= 128 }
                header.append(byte)
            }
            let compressed = try GitDeflate.encode(object.data, maximumBytes: maximumObjectBytes)
            guard header.count <= maximumBytes - pack.count,
                  compressed.count <= maximumBytes - pack.count - header.count else { throw GitWireError.responseTooLarge }
            pack += header; pack += compressed
        }
        let checksum = sha256 ? Data(SHA256.hash(data: pack)) : Data(Insecure.SHA1.hash(data: pack))
        guard checksum.count <= maximumBytes - pack.count else { throw GitWireError.responseTooLarge }
        return pack + checksum
    }
}
