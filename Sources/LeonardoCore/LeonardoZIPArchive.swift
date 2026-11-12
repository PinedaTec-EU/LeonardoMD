import CLeonardoZlib
import Foundation

/// Conventional ZIP32 transport. Stored and raw DEFLATE entries are supported.
/// All entries are checked and decompressed before the caller writes any files.
enum LeonardoZIPArchive {
    static let maximumArchiveBytes = 64 * 1_024 * 1_024
    static let maximumExpandedBytes = 32 * 1_024 * 1_024
    static let maximumEntries = 2_048
    static let maximumDirectories = maximumEntries
    static let maximumPathComponents = 64

    struct Entry {
        let name: String
        let data: Data
    }

    static func read(_ data: Data) throws -> [Entry] {
        guard data.count >= 22, data.count <= maximumArchiveBytes else { throw failure("Invalid archive size") }
        let lower = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: lower, by: -1).first(where: {
            data.u32($0) == 0x06054b50 && $0 + 22 + Int(data.u16($0 + 20)) == data.count
        }) else { throw failure("Missing ZIP directory") }
        let count = Int(data.u16(end + 10))
        let offset = Int(data.u32(end + 16))
        let directorySize = Int(data.u32(end + 12))
        guard data.u16(end + 4) == 0, data.u16(end + 6) == 0,
              data.u16(end + 8) == count, count > 0, count <= maximumEntries,
              offset + directorySize == end else { throw failure("Unsupported ZIP directory") }
        var cursor = offset
        var names = Set<String>()
        var entries: [Entry] = []
        var total = 0
        for _ in 0..<count {
            guard cursor + 46 <= end, data.u32(cursor) == 0x02014b50 else { throw failure("Invalid ZIP entry") }
            let nameLength = Int(data.u16(cursor + 28))
            let next = cursor + 46 + nameLength + Int(data.u16(cursor + 30)) + Int(data.u16(cursor + 32))
            guard next <= end,
                  let name = String(data: data.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8),
                  safePath(name)
            else { throw failure("Unsafe or duplicate ZIP path") }
            let isDirectory = name.hasSuffix("/")
            if !isDirectory {
                guard names.insert(collisionKey(name)).inserted else { throw failure("Unsafe or duplicate ZIP path") }
            }
            let flags = data.u16(cursor + 8)
            let method = data.u16(cursor + 10)
            let mode = (data.u32(cursor + 38) >> 16) & 0xf000
            guard flags & 0x2041 == 0, method == 0 || method == 8,
                  mode == 0 || mode == 0x8000 || (mode == 0x4000 && isDirectory)
            else { throw failure("Encrypted, linked or unsupported ZIP entry") }
            let expanded = Int(data.u32(cursor + 24))
            total += expanded
            guard expanded <= maximumExpandedBytes, total <= maximumExpandedBytes else { throw failure("ZIP expansion limit exceeded") }
            let value = try entryData(data, directory: cursor, directoryStart: offset, name: name, method: method)
            if !isDirectory { entries.append(Entry(name: name, data: value)) }
            cursor = next
        }
        guard cursor == end else { throw failure("Unexpected ZIP directory contents") }
        try validateDirectoryBudget(entries)
        let files = Set(entries.map { collisionKey($0.name) })
        for entry in entries {
            var parent = (entry.name as NSString).deletingLastPathComponent
            while !parent.isEmpty {
                guard !files.contains(collisionKey(parent)) else { throw failure("Conflicting ZIP paths") }
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return entries
    }

    private static func entryData(_ data: Data, directory: Int, directoryStart: Int, name: String, method: UInt16) throws -> Data {
        let local = Int(data.u32(directory + 42))
        let compressed = Int(data.u32(directory + 20))
        let expanded = Int(data.u32(directory + 24))
        guard local + 30 <= directoryStart, data.u32(local) == 0x04034b50,
              data.u16(local + 8) == method, data.u16(local + 6) == data.u16(directory + 8)
        else { throw failure("Invalid ZIP local header") }
        let length = Int(data.u16(local + 26))
        let start = local + 30 + length + Int(data.u16(local + 28))
        guard local + 30 + length <= directoryStart, start + compressed <= directoryStart,
              String(data: data.subdata(in: local + 30..<local + 30 + length), encoding: .utf8) == name
        else { throw failure("Mismatched ZIP entry") }
        let input = data.subdata(in: start..<start + compressed)
        let result: Data
        if method == 0 {
            guard compressed == expanded else { throw failure("Invalid stored entry size") }
            result = input
        } else {
            var output = Data(count: max(1, expanded))
            var written = 0
            var consumed = 0
            let status = output.withUnsafeMutableBytes { destination in
                input.withUnsafeBytes { source in
                    leonardo_zip_inflate(source.bindMemory(to: UInt8.self).baseAddress, input.count,
                        destination.bindMemory(to: UInt8.self).baseAddress, max(1, expanded), &written, &consumed)
                }
            }
            guard status == 1, written == expanded, consumed == compressed else { throw failure("Invalid compressed ZIP data") }
            result = output.prefix(expanded)
        }
        guard crc(result) == data.u32(directory + 16) else { throw failure("ZIP checksum mismatch") }
        return result
    }

    static func write(_ entries: [Entry]) throws -> Data {
        guard !entries.isEmpty, entries.count <= maximumEntries else { throw failure("Invalid ZIP entry count") }
        try validateDirectoryBudget(entries)
        var output = Data()
        var directory = Data()
        var total = 0
        var names = Set<String>()
        for entry in entries.sorted(by: { $0.name < $1.name }) {
            guard safePath(entry.name), !entry.name.hasSuffix("/"), entry.name.utf8.count <= 65_535,
                  names.insert(collisionKey(entry.name)).inserted else { throw failure("Unsafe or duplicate ZIP path") }
            total += entry.data.count
            guard total <= maximumExpandedBytes else { throw failure("Package exceeds export size limit") }
            let name = Data(entry.name.utf8)
            let checksum = crc(entry.data)
            let position = output.count
            output.put32(0x04034b50); output.put16(20); output.put16(0x800); output.put16(0)
            output.put16(0); output.put16(0x21); output.put32(checksum)
            output.put32(entry.data.count); output.put32(entry.data.count)
            output.put16(name.count); output.put16(0); output.append(name); output.append(entry.data)
            directory.put32(0x02014b50); directory.put16(20); directory.put16(20)
            directory.put16(0x800); directory.put16(0); directory.put16(0); directory.put16(0x21)
            directory.put32(checksum); directory.put32(entry.data.count); directory.put32(entry.data.count)
            directory.put16(name.count); directory.put16(0); directory.put16(0); directory.put16(0)
            directory.put16(0); directory.put32(0); directory.put32(position); directory.append(name)
        }
        let position = output.count
        output.append(directory)
        output.put32(0x06054b50); output.put16(0); output.put16(0)
        output.put16(entries.count); output.put16(entries.count)
        output.put32(directory.count); output.put32(position); output.put16(0)
        guard output.count <= maximumArchiveBytes else { throw failure("Package exceeds archive size limit") }
        return output
    }

    private static func validateDirectoryBudget(_ entries: [Entry]) throws {
        var directories: [String: String] = [:]
        for entry in entries {
            var prefix = ""
            for component in entry.name.split(separator: "/").dropLast() {
                prefix = prefix.isEmpty ? String(component) : prefix + "/" + component
                let key = collisionKey(prefix)
                if let previous = directories[key], !previous.utf8.elementsEqual(prefix.utf8) {
                    throw failure("Ambiguous ZIP directory paths")
                }
                directories[key] = prefix
                guard directories.count <= maximumDirectories else {
                    throw failure("ZIP directory expansion limit exceeded")
                }
            }
        }
    }

    static func safePath(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
              !name.contains(":"), !name.unicodeScalars.contains(where: { $0.value < 32 }) else { return false }
        let path = name.hasSuffix("/") ? String(name.dropLast()) : name
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= maximumPathComponents else { return false }
        return components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func collisionKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func crc(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { leonardo_crc32($0.bindMemory(to: UInt8.self).baseAddress, data.count) }
    }

    static func failure(_ reason: String) -> LeonardoPackageError { .invalidArchive(reason) }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
    mutating func put16<T: BinaryInteger>(_ value: T) {
        let number = UInt16(value)
        append(UInt8(truncatingIfNeeded: number)); append(UInt8(truncatingIfNeeded: number >> 8))
    }
    mutating func put32<T: BinaryInteger>(_ value: T) {
        let number = UInt32(value)
        put16(UInt16(truncatingIfNeeded: number)); put16(UInt16(truncatingIfNeeded: number >> 16))
    }
}
