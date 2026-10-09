import Foundation

public struct GitReference: Equatable, Sendable {
    public let name: String
    public let objectID: String?
    public let symbolicTarget: String?

    public static func isValidName(_ name: String) -> Bool {
        if name == "HEAD" { return true }
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        return name.hasPrefix("refs/") && name.utf8.count <= 4_096
            && !name.hasSuffix(".") && !name.contains("..") && !name.contains("@{")
            && !name.utf8.contains(where: { $0 < 33 || $0 == 127 || [126, 94, 58, 63, 42, 91, 92].contains($0) })
            && components.allSatisfy { !$0.isEmpty && !$0.hasPrefix(".") && !$0.hasSuffix(".lock") }
    }
}

public extension GitV2Capabilities {
    func referenceRequest() throws -> Data {
        try requireFolderTransfer()
        var request = try GitPacket.data(Data("command=ls-refs\n".utf8)).encoded()
        if let format = values["object-format"] {
            request += try GitPacket.data(Data("object-format=\(format)\n".utf8)).encoded()
        }
        request += try GitPacket.delimiter.encoded()
        var arguments = ["symrefs", "peel", "ref-prefix HEAD", "ref-prefix refs/heads/"]
        if values["ls-refs"]?.split(separator: " ").contains("unborn") == true { arguments.append("unborn") }
        for argument in arguments { request += try GitPacket.data(Data((argument + "\n").utf8)).encoded() }
        request += try GitPacket.flush.encoded()
        return request
    }

    func references(response: Data) throws -> [GitReference] {
        try requireFolderTransfer()
        let packets = try GitPacket.decode(response)
        guard packets.last == .flush else { throw GitWireError.invalidAdvertisement }
        var seen: Set<String> = []
        var references: [GitReference] = []
        for packet in packets.dropLast() {
            guard case .data(let data) = packet, var line = String(data: data, encoding: .utf8) else {
                throw GitWireError.invalidAdvertisement
            }
            if line.hasSuffix("\n") { line.removeLast() }
            guard !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw GitWireError.invalidAdvertisement
            }
            let fields = line.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 2, fields.allSatisfy({ !$0.isEmpty }), GitReference.isValidName(fields[1]),
                  seen.insert(fields[1]).inserted else { throw GitWireError.invalidAdvertisement }
            let unborn = fields[0] == "unborn"
            guard unborn ? values["ls-refs"]?.split(separator: " ").contains("unborn") == true : isValidObjectID(fields[0]) else {
                throw GitWireError.invalidObjectID
            }
            var target: String?
            var peeled = false
            for field in fields.dropFirst(2) {
                if field.hasPrefix("symref-target:") {
                    let candidate = String(field.dropFirst("symref-target:".count))
                    guard target == nil, candidate != "HEAD", GitReference.isValidName(candidate) else { throw GitWireError.invalidAdvertisement }
                    target = candidate
                } else if field.hasPrefix("peeled:") {
                    guard !peeled, isValidObjectID(String(field.dropFirst("peeled:".count))) else { throw GitWireError.invalidAdvertisement }
                    peeled = true
                } else { throw GitWireError.invalidAdvertisement }
            }
            guard !unborn || (fields[1] == "HEAD" && target != nil && !peeled) else { throw GitWireError.invalidAdvertisement }
            // A server may ignore ref-prefix, so enforce the requested categories locally.
            if fields[1] == "HEAD" || fields[1].hasPrefix("refs/heads/") {
                references.append(GitReference(name: fields[1], objectID: unborn ? nil : fields[0], symbolicTarget: target))
            }
        }
        return references.sorted { $0.name < $1.name }
    }

}
