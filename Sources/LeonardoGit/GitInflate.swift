import Foundation
import CLeonardoZlib

enum GitInflate {
    static func decode(_ input: Data, expectedBytes: Int, maximumBytes: Int) throws -> (data: Data, consumed: Int) {
        guard expectedBytes >= 0, maximumBytes >= 0, expectedBytes <= maximumBytes, expectedBytes <= Int(UInt32.max) else { throw GitWireError.responseTooLarge }
        guard !input.isEmpty, input.count <= Int(UInt32.max) else { throw GitWireError.invalidPack }
        var output = Data(count: max(expectedBytes, 1))
        var written = 0
        var consumed = 0
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                leonardo_inflate(source.bindMemory(to: UInt8.self).baseAddress, input.count,
                    destination.bindMemory(to: UInt8.self).baseAddress, destination.count, &written, &consumed)
            }
        }
        guard status == 1, written == expectedBytes, consumed > 0, consumed <= input.count else { throw GitWireError.invalidPack }
        output.count = written
        return (output, consumed)
    }
}
