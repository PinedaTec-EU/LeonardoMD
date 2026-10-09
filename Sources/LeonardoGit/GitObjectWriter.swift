import Foundation
import CryptoKit

extension GitObject {
    public static func create(kind: Kind, data: Data, sha256: Bool = false) -> GitObject {
        let canonical = Data("\(kind.rawValue) \(data.count)\0".utf8) + data
        let digest = sha256 ? Data(SHA256.hash(data: canonical)) : Data(Insecure.SHA1.hash(data: canonical))
        return GitObject(id: digest.map { String(format: "%02x", $0) }.joined(), kind: kind, data: data)
    }
}

extension GitTree {
    static func create(entries: [GitTreeEntry], sha256: Bool) throws -> GitObject {
        var data = Data()
        let sorted = entries.sorted { lhs, rhs in
            let a = Array(lhs.name.utf8) + [lhs.kind == .folder ? UInt8(47) : 0]
            let b = Array(rhs.name.utf8) + [rhs.kind == .folder ? UInt8(47) : 0]
            return a.lexicographicallyPrecedes(b)
        }
        for entry in sorted {
            guard entry.objectID.count == (sha256 ? 64 : 40) else { throw GitWireError.invalidObjectID }
            let mode: String
            switch entry.kind {
            case .folder: mode = "40000"
            case .file: mode = entry.executable ? "100755" : "100644"
            case .symbolicLink: mode = "120000"
            case .submodule: mode = "160000"
            }
            data += Data("\(mode) \(entry.name)\0".utf8)
            let bytes = Array(entry.objectID.utf8)
            func digit(_ value: UInt8) throws -> UInt8 {
                switch value {
                case 48...57: return value - 48
                case 97...102: return value - 97 + 10
                default: throw GitWireError.invalidObjectID
                }
            }
            for i in stride(from: 0, to: bytes.count, by: 2) {
                data.append(try digit(bytes[i]) << 4 | digit(bytes[i + 1]))
            }
        }
        let object = GitObject.create(kind: .tree, data: data, sha256: sha256)
        _ = try Self.entries(in: object)
        return object
    }
}
