import Foundation

/// Response to a fresh `fetch` with `done`, without existing shallow boundaries or URI requests.
public struct GitFetchResponse: Sendable {
    public let pack: Data
    public let shallowCommits: Set<String>
    public let objectCount: UInt32

    public init(response: Data, capabilities: GitV2Capabilities, maximumPackBytes: Int = 64 * 1_024 * 1_024,
                maximumWireBytes: Int = 80 * 1_024 * 1_024, maximumObjects: UInt32 = 100_000) throws {
        try capabilities.requireFolderTransfer()
        let packets = try GitPacket.commandResponse(response, maximumBytes: maximumWireBytes)
        guard packets.last == .flush else { throw GitWireError.invalidFetchResponse }
        enum State { case header, shallow, pack }
        var state = State.header
        var sawShallow = false
        var sawPack = false
        var shallow: Set<String> = []
        var pack = Data()
        for packet in packets.dropLast() {
            if packet == .delimiter {
                guard state == .shallow else { throw GitWireError.invalidFetchResponse }
                state = .header
                continue
            }
            guard case .data(let data) = packet else { throw GitWireError.invalidFetchResponse }
            switch state {
            case .header:
                guard var text = String(data: data, encoding: .utf8) else { throw GitWireError.invalidFetchResponse }
                if text.hasSuffix("\n") { text.removeLast() }
                if text == "shallow-info", !sawShallow {
                    sawShallow = true
                    state = .shallow
                } else if text == "packfile", !sawPack {
                    sawPack = true
                    state = .pack
                } else { throw GitWireError.invalidFetchResponse }
            case .shallow:
                guard var line = String(data: data, encoding: .utf8) else { throw GitWireError.invalidFetchResponse }
                if line.hasSuffix("\n") { line.removeLast() }
                guard line.hasPrefix("shallow ") else { throw GitWireError.invalidFetchResponse }
                let oid = String(line.dropFirst(8))
                guard capabilities.isValidObjectID(oid), shallow.insert(oid).inserted else { throw GitWireError.invalidFetchResponse }
            case .pack:
                guard let channel = data.first else { throw GitWireError.invalidFetchResponse }
                switch channel {
                case 1:
                    let body = data.dropFirst()
                    guard maximumPackBytes >= 0, body.count <= maximumPackBytes - pack.count else { throw GitWireError.responseTooLarge }
                    pack.append(body)
                case 2: break // Progress is untrusted prose, never instructions or corpus data.
                case 3: throw GitWireError.remoteFailure
                default: throw GitWireError.invalidFetchResponse
                }
            }
        }
        guard sawPack, state == .pack else { throw GitWireError.invalidPack }
        let count = try GitPackEnvelope.objectCount(in: pack, sha256: capabilities.values["object-format"] == "sha256",
                                                   maximumBytes: maximumPackBytes, maximumObjects: maximumObjects)
        self.pack = pack
        self.shallowCommits = shallow
        self.objectCount = count
    }
}
