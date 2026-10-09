import Foundation
import CryptoKit

public struct GitObject: Sendable, Equatable {
    public enum Kind: String, Sendable { case commit, tree, blob, tag }
    public let id: String
    public let kind: Kind
    public let data: Data
}

/// Decodes a self-contained pack. Thin packs are deliberately rejected.
public enum GitPack {
    public struct Limits: Sendable {
        public var objectBytes = 20 * 1_024 * 1_024
        public var totalBytes = 200 * 1_024 * 1_024
        public var deltaDepth = 64
        public init() {}
    }

    private enum Base: Hashable { case offset(Int), id(String) }
    private struct Entry { let offset: Int; let kind: GitObject.Kind?; let base: Base?; let data: Data }

    public static func decode(_ response: GitFetchResponse, sha256: Bool = false, limits: Limits = Limits()) throws -> [GitObject] {
        guard limits.objectBytes >= 0, limits.totalBytes >= 0, limits.deltaDepth >= 0 else { throw GitWireError.responseTooLarge }
        let entries = try read(response, sha256: sha256, limits: limits)
        var waiting: [Base: [Int]] = [:]
        var resolved: [Int: (GitObject, Int)] = [:]
        var queue: [Int] = []
        var total = 0
        func make(_ kind: GitObject.Kind, _ data: Data) -> GitObject {
            let content = Data("\(kind.rawValue) \(data.count)\0".utf8) + data
            let digest = sha256 ? Data(SHA256.hash(data: content)) : Data(Insecure.SHA1.hash(data: content))
            return GitObject(id: digest.map { String(format: "%02x", $0) }.joined(), kind: kind, data: data)
        }
        func insert(_ index: Int, _ object: GitObject, depth: Int) throws {
            guard object.data.count <= limits.totalBytes - total else { throw GitWireError.responseTooLarge }
            total += object.data.count
            resolved[index] = (object, depth)
            queue.append(index)
        }
        for (index, entry) in entries.enumerated() {
            if let kind = entry.kind { try insert(index, make(kind, entry.data), depth: 0) }
            else if let base = entry.base { waiting[base, default: []].append(index) }
        }
        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]; cursor += 1
            guard let (object, depth) = resolved[index] else { throw GitWireError.invalidPack }
            for key in [Base.offset(entries[index].offset), Base.id(object.id)] {
                for child in waiting.removeValue(forKey: key) ?? [] {
                    guard depth < limits.deltaDepth else { throw GitWireError.responseTooLarge }
                    let data = try GitDelta.apply(entries[child].data, to: object.data, maximumResultBytes: limits.objectBytes)
                    try insert(child, make(object.kind, data), depth: depth + 1)
                }
            }
        }
        guard resolved.count == entries.count else { throw GitWireError.invalidPack }
        return try entries.indices.map { index in
            guard let object = resolved[index]?.0 else { throw GitWireError.invalidPack }
            return object
        }
    }

    private static func read(_ response: GitFetchResponse, sha256: Bool, limits: Limits) throws -> [Entry] {
        let pack = response.pack
        let end = pack.count - (sha256 ? 32 : 20)
        guard end >= 12 else { throw GitWireError.invalidPack }
        var cursor = 12
        func byte() throws -> UInt8 {
            guard cursor < end else { throw GitWireError.invalidPack }
            defer { cursor += 1 }; return pack[cursor]
        }
        var entries: [Entry] = []
        var inflatedBytes = 0
        for _ in 0..<response.objectCount {
            let offset = cursor
            var value = try byte()
            let type = (value >> 4) & 7
            var size = Int(value & 15)
            var shift = 4
            while value & 128 != 0 {
                value = try byte()
                let part = Int(value & 127)
                guard shift < Int.bitWidth - 1, part <= (Int.max >> shift) else { throw GitWireError.invalidPack }
                size |= part << shift; shift += 7
            }
            guard size <= limits.objectBytes, size <= limits.totalBytes - inflatedBytes else { throw GitWireError.responseTooLarge }
            let kind: GitObject.Kind?
            var base: Base?
            switch type {
            case 1: kind = .commit
            case 2: kind = .tree
            case 3: kind = .blob
            case 4: kind = .tag
            case 6:
                kind = nil
                value = try byte()
                var distance = Int(value & 127)
                while value & 128 != 0 {
                    value = try byte()
                    guard distance < (Int.max >> 7) else { throw GitWireError.invalidPack }
                    distance = ((distance + 1) << 7) | Int(value & 127)
                }
                guard distance > 0, distance <= offset - 12 else { throw GitWireError.invalidPack }
                base = .offset(offset - distance)
            case 7:
                kind = nil
                let count = sha256 ? 32 : 20
                guard count <= end - cursor else { throw GitWireError.invalidPack }
                base = .id(pack[cursor..<cursor + count].map { String(format: "%02x", $0) }.joined())
                cursor += count
            default: throw GitWireError.invalidPack
            }
            let decoded = try GitInflate.decode(pack[cursor..<end], expectedBytes: size, maximumBytes: limits.objectBytes)
            cursor += decoded.consumed
            inflatedBytes += size
            entries.append(Entry(offset: offset, kind: kind, base: base, data: decoded.data))
        }
        guard cursor == end else { throw GitWireError.invalidPack }
        return entries
    }
}
