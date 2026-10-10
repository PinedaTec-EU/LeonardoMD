import Foundation

public struct GitTreeEntry: Sendable, Equatable {
    public enum Kind: Sendable { case folder, file, symbolicLink, submodule }
    public let name: String
    public let objectID: String
    public let kind: Kind
    public let executable: Bool
}

public enum GitTree {
    public static func entries(in object: GitObject, maximumEntries: Int = 10_000) throws -> [GitTreeEntry] {
        guard object.kind == .tree, [40, 64].contains(object.id.count) else { throw GitWireError.invalidPack }
        let bytes = Array(object.data)
        let hashBytes = object.id.count / 2
        var cursor = 0
        var entries: [GitTreeEntry] = []
        var names: Set<String> = []
        func token(until separator: UInt8) throws -> String {
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != separator { cursor += 1 }
            guard cursor < bytes.count, let text = String(bytes: bytes[start..<cursor], encoding: .utf8) else {
                throw GitWireError.invalidPack
            }
            cursor += 1
            return text
        }
        while cursor < bytes.count {
            guard entries.count < maximumEntries else { throw GitWireError.responseTooLarge }
            let mode = try token(until: 32)
            let name = try token(until: 0)
            guard !name.isEmpty, name != ".", name != "..", name.utf8.count <= 4_096,
                  !name.contains("/"), !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted,
                  hashBytes <= bytes.count - cursor else { throw GitWireError.invalidPack }
            let id = bytes[cursor..<cursor + hashBytes].map { String(format: "%02x", $0) }.joined()
            cursor += hashBytes
            let kind: GitTreeEntry.Kind
            switch mode {
            case "40000": kind = .folder
            case "100644", "100755": kind = .file
            case "120000": kind = .symbolicLink
            case "160000": kind = .submodule
            default: throw GitWireError.invalidPack
            }
            entries.append(GitTreeEntry(name: name, objectID: id, kind: kind, executable: mode == "100755"))
        }
        return entries
    }
}
