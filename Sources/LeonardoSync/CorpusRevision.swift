import Foundation
import CryptoKit

/// Content identity for direct synchronization. Length framing separates paths/content,
/// and buffer ownership is included so saving a draft also invalidates a reviewed comparison.
public enum CorpusRevision {
    public static func make(files: [CorpusFile]) -> String {
        var hash = SHA256()
        hash.update(data: Data("LeonardoMD corpus revision 1\0".utf8))
        for file in files.sorted(by: { $0.path < $1.path }) {
            let path = Data(file.path.utf8)
            hash.update(data: length(path.count))
            hash.update(data: path)
            hash.update(data: Data([file.isUnsavedBuffer ? 1 : 0]))
            hash.update(data: length(file.content.count))
            hash.update(data: file.content)
        }
        return "sha256:" + hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func length(_ count: Int) -> Data {
        var value = UInt64(count).bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
