import Foundation
import CLeonardoZlib

enum GitDeflate {
    static func encode(_ data: Data, maximumBytes: Int = GitPack.Limits().objectBytes) throws -> Data {
        guard maximumBytes >= 0, data.count <= maximumBytes, data.count <= Int(UInt32.max) else { throw GitWireError.responseTooLarge }
        let bound = leonardo_compress_bound(data.count)
        guard bound > 0, bound <= Int(UInt32.max) else { throw GitWireError.responseTooLarge }
        var output = Data(count: bound)
        var written = 0
        let status = data.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                leonardo_deflate(source.bindMemory(to: UInt8.self).baseAddress, data.count,
                                destination.bindMemory(to: UInt8.self).baseAddress, bound, &written)
            }
        }
        guard status == 0, written <= bound else { throw GitWireError.invalidPack }
        output.count = written
        return output
    }
}
