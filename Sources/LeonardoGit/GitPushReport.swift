import Foundation

public enum GitPushReport {
    public static func validate(_ response: Data, branch: String) throws {
        let packets = try GitPacket.decode(response, maximumBytes: 1_024 * 1_024)
        guard packets.count == 3, packets.last == .flush else { throw GitPushError.invalidResponse }
        var lines: [String] = []
        for packet in packets.dropLast() {
            guard case .data(let data) = packet, var line = String(data: data, encoding: .utf8) else { throw GitPushError.invalidResponse }
            if line.hasSuffix("\n") { line.removeLast() }
            guard !line.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw GitPushError.invalidResponse }
            lines.append(line)
        }
        guard lines[0].hasPrefix("unpack ") else { throw GitPushError.invalidResponse }
        guard lines[0] == "unpack ok" else { throw GitPushError.rejected }
        if lines[1].hasPrefix("ng \(branch) ") { throw GitPushError.rejected }
        guard lines[1] == "ok \(branch)" else { throw GitPushError.invalidResponse }
    }
}
