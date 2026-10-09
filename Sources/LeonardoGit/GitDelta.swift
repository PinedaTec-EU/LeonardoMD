import Foundation

/// Reconstructs a canonical object after its base has been resolved by the pack decoder.
public enum GitDelta {
    public static func apply(_ delta: Data, to base: Data, maximumResultBytes: Int = 20 * 1_024 * 1_024) throws -> Data {
        var cursor = delta.startIndex
        func byte() throws -> UInt8 {
            guard cursor < delta.endIndex else { throw GitWireError.invalidDelta }
            defer { cursor = delta.index(after: cursor) }
            return delta[cursor]
        }
        func size() throws -> Int {
            var result = 0
            var shift = 0
            while true {
                let current = try byte()
                let value = Int(current & 0x7f)
                guard shift < Int.bitWidth - 1, value <= Int.max >> shift else { throw GitWireError.invalidDelta }
                result |= value << shift
                if current & 0x80 == 0 { return result }
                shift += 7
            }
        }
        guard try size() == base.count else { throw GitWireError.invalidDelta }
        let resultSize = try size()
        guard maximumResultBytes >= 0, resultSize <= maximumResultBytes else { throw GitWireError.responseTooLarge }
        var result = Data()
        result.reserveCapacity(resultSize)
        while cursor < delta.endIndex {
            let opcode = try byte()
            guard opcode != 0 else { throw GitWireError.invalidDelta }
            if opcode & 0x80 != 0 {
                var offset = 0
                var count = 0
                for bit in 0..<4 where opcode & (1 << bit) != 0 { offset |= Int(try byte()) << (bit * 8) }
                for bit in 0..<3 where opcode & (1 << (bit + 4)) != 0 { count |= Int(try byte()) << (bit * 8) }
                if count == 0 { count = 0x10000 }
                guard offset <= base.count, count <= base.count - offset, count <= resultSize - result.count else {
                    throw GitWireError.invalidDelta
                }
                let start = base.index(base.startIndex, offsetBy: offset)
                result.append(base[start..<base.index(start, offsetBy: count)])
            } else {
                let count = Int(opcode)
                guard count <= delta.distance(from: cursor, to: delta.endIndex), count <= resultSize - result.count else {
                    throw GitWireError.invalidDelta
                }
                let end = delta.index(cursor, offsetBy: count)
                result.append(delta[cursor..<end])
                cursor = end
            }
        }
        guard result.count == resultSize else { throw GitWireError.invalidDelta }
        return result
    }
}
