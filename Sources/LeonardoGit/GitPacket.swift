import Foundation

public enum GitWireError: Error, Equatable, Sendable {
    case invalidPacket, truncatedPacket, responseTooLarge, invalidAdvertisement
    case filteringUnavailable, invalidObjectID, unsupportedObjectFormat
    case invalidFetchResponse, remoteFailure, invalidPack
    case invalidDelta
}

public enum GitPacket: Equatable, Sendable {
    case data(Data), flush, delimiter, responseEnd

    public func encoded() throws -> Data {
        switch self {
        case .flush: return Data("0000".utf8)
        case .delimiter: return Data("0001".utf8)
        case .responseEnd: return Data("0002".utf8)
        case .data(let payload):
            guard payload.count <= 65_516 else { throw GitWireError.invalidPacket }
            return Data(String(format: "%04x", payload.count + 4).utf8) + payload
        }
    }

    public static func decode(_ input: Data, maximumBytes: Int = 2 * 1_024 * 1_024, maximumPackets: Int = 32_768) throws -> [GitPacket] {
        guard maximumBytes >= 0, maximumPackets >= 0, input.count <= maximumBytes else { throw GitWireError.responseTooLarge }
        var packets: [GitPacket] = []
        var cursor = input.startIndex
        while cursor < input.endIndex {
            guard packets.count < maximumPackets else { throw GitWireError.responseTooLarge }
            guard input.distance(from: cursor, to: input.endIndex) >= 4 else { throw GitWireError.truncatedPacket }
            var length = 0
            for _ in 0..<4 {
                let byte = input[cursor]
                let digit: Int
                switch byte {
                case 48...57: digit = Int(byte - 48)
                case 97...102: digit = Int(byte - 97) + 10
                default: throw GitWireError.invalidPacket
                }
                length = length * 16 + digit
                cursor = input.index(after: cursor)
            }
            switch length {
            case 0: packets.append(.flush)
            case 1: packets.append(.delimiter)
            case 2: packets.append(.responseEnd)
            case 4...65_520:
                let count = length - 4
                guard input.distance(from: cursor, to: input.endIndex) >= count else { throw GitWireError.truncatedPacket }
                let end = input.index(cursor, offsetBy: count)
                packets.append(.data(Data(input[cursor..<end])))
                cursor = end
            default: throw GitWireError.invalidPacket
            }
        }
        return packets
    }

    static func commandResponse(_ input: Data, maximumBytes: Int = 2 * 1_024 * 1_024) throws -> [GitPacket] {
        var packets = try decode(input, maximumBytes: maximumBytes)
        if packets.last == .responseEnd { packets.removeLast() }
        guard packets.last == .flush else { throw GitWireError.invalidPacket }
        return packets
    }
}
