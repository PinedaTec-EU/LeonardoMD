import Foundation

/// Rejects unsupported partial transfer before requesting any repository objects.
public struct GitV2Capabilities: Sendable {
    public let values: [String: String]

    public init(advertisement: Data) throws {
        var packets = try GitPacket.decode(advertisement)
        if packets.first == .data(Data("# service=git-upload-pack\n".utf8)) {
            guard packets.count >= 4, packets[1] == .flush else { throw GitWireError.invalidAdvertisement }
            packets.removeFirst(2)
        }
        guard packets.first == .data(Data("version 2\n".utf8)) || packets.first == .data(Data("version 2".utf8)),
              packets.last == .flush else { throw GitWireError.invalidAdvertisement }
        var values: [String: String] = [:]
        for packet in packets.dropFirst().dropLast() {
            guard case .data(let data) = packet, var line = String(data: data, encoding: .utf8) else {
                throw GitWireError.invalidAdvertisement
            }
            if line.hasSuffix("\n") { line.removeLast() }
            guard !line.isEmpty, !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw GitWireError.invalidAdvertisement
            }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(parts[0])
            guard !name.isEmpty, name.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }),
                  values[name] == nil else { throw GitWireError.invalidAdvertisement }
            values[name] = parts.count == 2 ? String(parts[1]) : ""
        }
        self.values = values
    }

    public func requireFolderTransfer() throws {
        guard values["ls-refs"] != nil,
              values["fetch"]?.split(separator: " ").contains("filter") == true,
              values["fetch"]?.split(separator: " ").contains("shallow") == true else { throw GitWireError.filteringUnavailable }
        guard ["sha1", "sha256"].contains(values["object-format"] ?? "sha1") else { throw GitWireError.unsupportedObjectFormat }
    }

    func isValidObjectID(_ value: String) -> Bool {
        value.utf8.count == ((values["object-format"] ?? "sha1") == "sha1" ? 40 : 64)
            && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && value.contains { $0 != "0" }
    }

    /// Fetches only the selected tip's commit/tree metadata; file contents remain omitted.
    /// A larger depth is used only for bounded ancestry proofs and never
    /// permits a blob-bearing or unbounded history transfer.
    public func metadataRequest(want objectID: String, depth: Int = 1) throws -> Data {
        try requireFolderTransfer()
        guard isValidObjectID(objectID), (1...1_024).contains(depth) else {
            throw GitWireError.invalidObjectID
        }
        return try fetchRequest(arguments: ["want \(objectID)\n", "deepen \(depth)\n", "filter blob:none\n", "done\n"])
    }

    /// Wants only explicitly selected file blobs. No commit traversal or fallback clone.
    public func selectedBlobRequest(objectIDs: [String]) throws -> Data {
        try requireFolderTransfer()
        guard !objectIDs.isEmpty, objectIDs.count <= 10_000 else { throw GitWireError.responseTooLarge }
        guard objectIDs.allSatisfy(isValidObjectID), Set(objectIDs).count == objectIDs.count else {
            throw GitWireError.invalidObjectID
        }
        return try fetchRequest(arguments: objectIDs.sorted().map { "want \($0)\n" } + ["done\n"])
    }

    private func fetchRequest(arguments: [String]) throws -> Data {
        var headers = ["command=fetch\n"]
        if let format = values["object-format"] { headers.append("object-format=\(format)\n") }
        var result = Data()
        for header in headers { result += try GitPacket.data(Data(header.utf8)).encoded() }
        result += try GitPacket.delimiter.encoded()
        for argument in arguments { result += try GitPacket.data(Data(argument.utf8)).encoded() }
        result += try GitPacket.flush.encoded()
        return result
    }
}
