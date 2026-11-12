import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct LeonardoFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

struct LeonardoExtractionOwnership: Equatable, Sendable {
    let root: LeonardoFileIdentity
    let parent: LeonardoFileIdentity
}

struct LeonardoSecureExtractionHooks {
    let beforeRootClaim: (() throws -> Void)?
    let afterRootClaim: (() throws -> Void)?
    let beforePathComponent: ((String) throws -> Void)?
    let beforeFileClaim: ((String) throws -> Void)?
    let beforeReturn: (() throws -> Void)?

    init(
        beforeRootClaim: (() throws -> Void)? = nil,
        afterRootClaim: (() throws -> Void)? = nil,
        beforePathComponent: ((String) throws -> Void)? = nil,
        beforeFileClaim: ((String) throws -> Void)? = nil,
        beforeReturn: (() throws -> Void)? = nil
    ) {
        self.beforeRootClaim = beforeRootClaim
        self.afterRootClaim = afterRootClaim
        self.beforePathComponent = beforePathComponent
        self.beforeFileClaim = beforeFileClaim
        self.beforeReturn = beforeReturn
    }
}

enum LeonardoSecureExtractionFailure: Error {
    case unsupported
    case destinationExists
    case unsafePath
    case systemCall(String, Int32)
    case identityChanged
    case foreignEntry
}

extension LeonardoSecureExtractionFailure {
    var packageError: LeonardoPackageError {
        switch self {
        case .destinationExists:
            return .destinationExists
        case .unsupported:
            return .invalidArchive("Secure extraction is unavailable on this platform")
        case .unsafePath:
            return .invalidArchive("Package extraction path is unsafe")
        case .systemCall(let operation, _):
            return .invalidArchive("Secure extraction failed during \(operation)")
        case .identityChanged:
            return .invalidArchive("The extraction destination changed while the package was being opened")
        case .foreignEntry:
            return .invalidArchive("An extraction path entry appeared before it could be claimed")
        }
    }
}

#if canImport(Darwin)
enum LeonardoSecureExtraction {
    static let maximumPathComponents = LeonardoZIPArchive.maximumPathComponents
    private static let systemPathBufferBytes = 4_096

    private struct AbsolutePath {
        let components: [String]

        init(_ url: URL) throws {
            guard url.isFileURL else { throw LeonardoSecureExtractionFailure.unsafePath }
            let path = url.path
            guard path.first == "/" else { throw LeonardoSecureExtractionFailure.unsafePath }
            let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !components.isEmpty, components.count <= LeonardoSecureExtraction.maximumPathComponents,
                  components.allSatisfy({ $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
                throw LeonardoSecureExtractionFailure.unsafePath
            }
            self.components = components
        }

        var leaf: String { components[components.count - 1] }
        var parent: ArraySlice<String> { components.dropLast() }
    }

    private struct RelativePath {
        let components: [String]

        init(_ name: String) throws {
            let components = name.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !components.isEmpty, components.count <= LeonardoSecureExtraction.maximumPathComponents,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") }) else {
                throw LeonardoSecureExtractionFailure.unsafePath
            }
            self.components = components
        }

        var leaf: String { components[components.count - 1] }
        var parent: ArraySlice<String> { components.dropLast() }
        var key: String { components.joined(separator: "/") }
    }

    private struct EntryMetadata {
        let identity: LeonardoFileIdentity
        let isDirectory: Bool
        let isSymbolicLink: Bool
        let owner: UInt32
    }

    private struct OpenDirectory {
        let fd: Int32
        let identity: LeonardoFileIdentity

        func close() { Darwin.close(fd) }
    }

    private struct ClaimedRoot {
        let parent: OpenDirectory
        let rootFD: Int32
        let rootIdentity: LeonardoFileIdentity
        let leaf: String
    }

    private struct DirectoryCursor {
        let current: Int32
        let opened: [Int32]

        func close() {
            for descriptor in opened.reversed() { Darwin.close(descriptor) }
        }
    }

    private struct CreatedEntries {
        var directories: [String: LeonardoFileIdentity] = [:]
        var files: [String: LeonardoFileIdentity] = [:]
    }

    static func extract(
        entries: [LeonardoZIPArchive.Entry],
        to destination: URL,
        hooks: LeonardoSecureExtractionHooks?
    ) throws -> LeonardoExtractionOwnership {
        let path = try AbsolutePath(destination)
        let parent = try openDirectory(path.parent)
        var claim: ClaimedRoot?
        var created = CreatedEntries()

        do {
            try hooks?.beforeRootClaim?()
            let root = try claimRoot(parent, leaf: path.leaf)
            claim = root
            try hooks?.afterRootClaim?()
            try extract(entries, into: root.rootFD, created: &created, hooks: hooks)
            try hooks?.beforeReturn?()
            try verifyCreatedEntries(created, root: root)
            try verifyRootAndParent(root, parentComponents: path.parent)
            let ownership = LeonardoExtractionOwnership(root: root.rootIdentity, parent: root.parent.identity)
            root.parent.close()
            Darwin.close(root.rootFD)
            return ownership
        } catch {
            if let root = claim {
                cleanup(created, root: root)
                root.parent.close()
                Darwin.close(root.rootFD)
            } else {
                parent.close()
            }
            throw error
        }
    }

    static func verifyWorkspace(at directoryURL: URL, ownership: LeonardoExtractionOwnership) throws {
        let path = try AbsolutePath(directoryURL)
        let parent = try openDirectory(path.parent)
        defer { parent.close() }
        guard parent.identity == ownership.parent,
              let rootMetadata = try metadata(at: parent.fd, name: path.leaf),
              rootMetadata.identity == ownership.root,
              rootMetadata.isDirectory,
              !rootMetadata.isSymbolicLink else {
            throw LeonardoSecureExtractionFailure.identityChanged
        }
        let rootFD = try openDirectoryComponent(parent.fd, path.leaf)
        defer { Darwin.close(rootFD) }
        guard try metadata(of: rootFD).identity == ownership.root else {
            throw LeonardoSecureExtractionFailure.identityChanged
        }
        try verifyParentPath(path.parent, identity: ownership.parent)
    }

    static func removeOwnedTemporaryWorkspace(at directoryURL: URL, ownership: LeonardoExtractionOwnership) {
        guard let path = try? AbsolutePath(directoryURL),
              let parent = try? openDirectory(path.parent) else { return }
        defer { parent.close() }
        guard parent.identity == ownership.parent,
              let rootMetadata = existingMetadata(at: parent.fd, name: path.leaf),
              rootMetadata.identity == ownership.root,
              rootMetadata.isDirectory,
              !rootMetadata.isSymbolicLink,
              let rootFD = try? openDirectoryComponent(parent.fd, path.leaf) else {
            return
        }
        guard let actualRoot = try? metadata(of: rootFD),
              actualRoot.identity == ownership.root else {
            Darwin.close(rootFD)
            return
        }
        defer { Darwin.close(rootFD) }
        removeDirectoryContents(rootFD)
        guard let current = existingMetadata(at: parent.fd, name: path.leaf),
              current.identity == ownership.root else { return }
        _ = unlinkat(parent.fd, path.leaf, AT_REMOVEDIR)
    }

    private static func claimRoot(_ parent: OpenDirectory, leaf: String) throws -> ClaimedRoot {
        let result = leaf.withCString { mkdirat(parent.fd, $0, mode_t(0o700)) }
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw LeonardoSecureExtractionFailure.destinationExists }
            throw LeonardoSecureExtractionFailure.systemCall("claim root", code)
        }
        guard let created = try metadata(at: parent.fd, name: leaf),
              created.isDirectory, !created.isSymbolicLink, created.owner == geteuid() else {
            throw LeonardoSecureExtractionFailure.identityChanged
        }
        do {
            let rootFD = try openDirectoryComponent(parent.fd, leaf)
            do {
                let rootMetadata = try metadata(of: rootFD)
                guard created.identity == rootMetadata.identity,
                      rootMetadata.isDirectory,
                      !rootMetadata.isSymbolicLink else {
                    throw LeonardoSecureExtractionFailure.identityChanged
                }
                return ClaimedRoot(parent: parent, rootFD: rootFD, rootIdentity: rootMetadata.identity, leaf: leaf)
            } catch {
                Darwin.close(rootFD)
                throw error
            }
        } catch {
            if let current = existingMetadata(at: parent.fd, name: leaf),
               current.identity == created.identity {
                _ = unlinkat(parent.fd, leaf, AT_REMOVEDIR)
            }
            throw error
        }
    }

    private static func extract(
        _ entries: [LeonardoZIPArchive.Entry],
        into rootFD: Int32,
        created: inout CreatedEntries,
        hooks: LeonardoSecureExtractionHooks?
    ) throws {
        for entry in entries {
            let path = try RelativePath(entry.name)
            try write(entry, at: path, rootFD: rootFD, created: &created, hooks: hooks)
        }
    }

    private static func write(
        _ entry: LeonardoZIPArchive.Entry,
        at path: RelativePath,
        rootFD: Int32,
        created: inout CreatedEntries,
        hooks: LeonardoSecureExtractionHooks?
    ) throws {
        let cursor = try openParent(path.parent, rootFD: rootFD, created: &created, hooks: hooks)
        defer { cursor.close() }
        try hooks?.beforeFileClaim?(entry.name)
        let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
        let descriptor = path.leaf.withCString {
            openat(cursor.current, $0, flags, mode_t(0o600))
        }
        guard descriptor >= 0 else {
            let code = errno
            if code == EEXIST { throw LeonardoSecureExtractionFailure.destinationExists }
            throw LeonardoSecureExtractionFailure.systemCall("create archive member", code)
        }
        let identity: LeonardoFileIdentity
        do {
            identity = try metadata(of: descriptor).identity
            created.files[path.key] = identity
            try write(entry.data, to: descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        Darwin.close(descriptor)
    }

    private static func openParent(
        _ components: ArraySlice<String>,
        rootFD: Int32,
        created: inout CreatedEntries,
        hooks: LeonardoSecureExtractionHooks?
    ) throws -> DirectoryCursor {
        var current = rootFD
        var opened: [Int32] = []
        var prefix: [String] = []
        do {
            for component in components {
                prefix.append(component)
                let key = prefix.joined(separator: "/")
                try hooks?.beforePathComponent?(key)
                let descriptor = try openOrCreateDirectory(component, key: key, at: current, created: &created)
                opened.append(descriptor)
                current = descriptor
            }
            return DirectoryCursor(current: current, opened: opened)
        } catch {
            for descriptor in opened.reversed() { Darwin.close(descriptor) }
            throw error
        }
    }

    private static func openOrCreateDirectory(
        _ component: String,
        key: String,
        at parentFD: Int32,
        created: inout CreatedEntries
    ) throws -> Int32 {
        let existing = try metadata(at: parentFD, name: component)
        if let existing {
            guard let expected = created.directories[key], expected == existing.identity,
                  existing.isDirectory, !existing.isSymbolicLink else {
                throw existing.isSymbolicLink ? LeonardoSecureExtractionFailure.unsafePath : .foreignEntry
            }
            let descriptor = try openDirectoryComponent(parentFD, component)
            guard try metadata(of: descriptor).identity == expected else {
                Darwin.close(descriptor)
                throw LeonardoSecureExtractionFailure.identityChanged
            }
            return descriptor
        }

        guard created.directories[key] == nil else {
            throw LeonardoSecureExtractionFailure.identityChanged
        }

        let result = component.withCString { mkdirat(parentFD, $0, mode_t(0o700)) }
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw LeonardoSecureExtractionFailure.foreignEntry }
            throw LeonardoSecureExtractionFailure.systemCall("create archive directory", code)
        }
        guard let createdMetadata = try metadata(at: parentFD, name: component),
              createdMetadata.isDirectory, !createdMetadata.isSymbolicLink,
              createdMetadata.owner == geteuid() else {
            throw LeonardoSecureExtractionFailure.identityChanged
        }
        created.directories[key] = createdMetadata.identity
        let descriptor = try openDirectoryComponent(parentFD, component)
        do {
            guard try metadata(of: descriptor).identity == createdMetadata.identity else {
                throw LeonardoSecureExtractionFailure.identityChanged
            }
            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private static func openDirectory(_ components: ArraySlice<String>) throws -> OpenDirectory {
        let rootFD = try openRootDirectory()
        var opened = [rootFD]
        var current = rootFD
        do {
            for (index, component) in components.enumerated() {
                let descriptor = try openPathComponent(current, component: component, isFirst: index == 0)
                opened.append(descriptor)
                current = descriptor
            }
            let result = OpenDirectory(fd: current, identity: try metadata(of: current).identity)
            for descriptor in opened.dropLast().reversed() { Darwin.close(descriptor) }
            return result
        } catch {
            for descriptor in opened.reversed() { Darwin.close(descriptor) }
            throw error
        }
    }

    private static func openRootDirectory() throws -> Int32 {
        let descriptor = "/".withCString { openat(AT_FDCWD, $0, directoryFlags) }
        guard descriptor >= 0 else {
            throw LeonardoSecureExtractionFailure.systemCall("open root", errno)
        }
        return descriptor
    }

    private static func openPathComponent(_ parentFD: Int32, component: String, isFirst: Bool) throws -> Int32 {
        if isFirst, component == "tmp" || component == "var",
           let link = try metadata(at: parentFD, name: component), link.isSymbolicLink {
            guard link.owner == 0, try isSystemAlias(component, at: parentFD) else {
                throw LeonardoSecureExtractionFailure.unsafePath
            }
            let privateFD = try openDirectoryComponent(parentFD, "private")
            defer { Darwin.close(privateFD) }
            return try openDirectoryComponent(privateFD, component)
        }
        return try openDirectoryComponent(parentFD, component)
    }

    private static func isSystemAlias(_ component: String, at parentFD: Int32) throws -> Bool {
        var buffer = [CChar](repeating: 0, count: systemPathBufferBytes)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            component.withCString { readlinkat(parentFD, $0, pointer.baseAddress, pointer.count) }
        }
        guard length >= 0 else { throw LeonardoSecureExtractionFailure.systemCall("read system alias", errno) }
        let actual = buffer.prefix(length).map { UInt8(bitPattern: $0) }
        let accepted = ["private/\(component)", "/private/\(component)"].map { Array($0.utf8) }
        return accepted.contains(actual)
    }

    private static func openDirectoryComponent(_ parentFD: Int32, _ component: String) throws -> Int32 {
        let descriptor = component.withCString { openat(parentFD, $0, directoryFlags) }
        guard descriptor >= 0 else {
            throw LeonardoSecureExtractionFailure.systemCall("open directory", errno)
        }
        return descriptor
    }

    private static func metadata(at parentFD: Int32, name: String) throws -> EntryMetadata? {
        var value = stat()
        let result = name.withCString { fstatat(parentFD, $0, &value, AT_SYMLINK_NOFOLLOW) }
        guard result == 0 else {
            let code = errno
            if code == ENOENT { return nil }
            throw LeonardoSecureExtractionFailure.systemCall("inspect path", code)
        }
        return metadata(from: value)
    }

    private static func metadata(of descriptor: Int32) throws -> EntryMetadata {
        var value = stat()
        guard fstat(descriptor, &value) == 0 else {
            throw LeonardoSecureExtractionFailure.systemCall("inspect descriptor", errno)
        }
        return metadata(from: value)
    }

    private static func existingMetadata(at parentFD: Int32, name: String) -> EntryMetadata? {
        do {
            return try metadata(at: parentFD, name: name)
        } catch {
            return nil
        }
    }

    private static func metadata(from value: stat) -> EntryMetadata {
        let mode = Int32(value.st_mode)
        return EntryMetadata(
            identity: LeonardoFileIdentity(device: UInt64(UInt32(bitPattern: value.st_dev)), inode: UInt64(value.st_ino)),
            isDirectory: mode & Int32(S_IFMT) == Int32(S_IFDIR),
            isSymbolicLink: mode & Int32(S_IFMT) == Int32(S_IFLNK),
            owner: UInt32(value.st_uid)
        )
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), data.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    throw LeonardoSecureExtractionFailure.systemCall("write archive member", errno)
                }
            }
        }
    }

    private static func verifyCreatedEntries(_ created: CreatedEntries, root: ClaimedRoot) throws {
        let entries = created.files.merging(created.directories, uniquingKeysWith: { first, _ in first })
        for (key, identity) in entries {
            let path = try RelativePath(key)
            let cursor = try openOwnedParent(path.parent, rootFD: root.rootFD, directories: created.directories)
            defer { cursor.close() }
            guard let current = try metadata(at: cursor.current, name: path.leaf),
                  current.identity == identity, !current.isSymbolicLink else {
                throw LeonardoSecureExtractionFailure.identityChanged
            }
        }
    }

    private static func verifyRootAndParent(_ root: ClaimedRoot, parentComponents: ArraySlice<String>) throws {
        guard try metadata(of: root.rootFD).identity == root.rootIdentity,
              let rootAtParent = try metadata(at: root.parent.fd, name: root.leaf),
              rootAtParent.identity == root.rootIdentity,
              rootAtParent.isDirectory,
              !rootAtParent.isSymbolicLink else {
            throw LeonardoSecureExtractionFailure.identityChanged
        }
        try verifyParentPath(parentComponents, identity: root.parent.identity)
    }

    private static func verifyParentPath(_ components: ArraySlice<String>, identity: LeonardoFileIdentity) throws {
        let current = try openDirectory(components)
        defer { current.close() }
        guard current.identity == identity else { throw LeonardoSecureExtractionFailure.identityChanged }
    }

    private static func cleanup(_ created: CreatedEntries, root: ClaimedRoot) {
        for key in created.files.keys.sorted(by: deeperPathFirst) {
            removeOwnedFile(key, identity: created.files[key]!, root: root, directories: created.directories)
        }
        for key in created.directories.keys.sorted(by: deeperPathFirst) {
            removeOwnedDirectory(key, identity: created.directories[key]!, root: root, directories: created.directories)
        }
        guard let current = existingMetadata(at: root.parent.fd, name: root.leaf),
              current.identity == root.rootIdentity else { return }
        _ = unlinkat(root.parent.fd, root.leaf, AT_REMOVEDIR)
    }

    private static func removeOwnedFile(
        _ key: String,
        identity: LeonardoFileIdentity,
        root: ClaimedRoot,
        directories: [String: LeonardoFileIdentity]
    ) {
        guard let path = try? RelativePath(key), let cursor = try? openOwnedParent(path.parent, rootFD: root.rootFD, directories: directories) else {
            return
        }
        defer { cursor.close() }
        guard let current = existingMetadata(at: cursor.current, name: path.leaf),
              current.identity == identity else { return }
        _ = unlinkat(cursor.current, path.leaf, 0)
    }

    private static func removeOwnedDirectory(
        _ key: String,
        identity: LeonardoFileIdentity,
        root: ClaimedRoot,
        directories: [String: LeonardoFileIdentity]
    ) {
        guard let path = try? RelativePath(key), let cursor = try? openOwnedParent(path.parent, rootFD: root.rootFD, directories: directories) else {
            return
        }
        defer { cursor.close() }
        guard let current = existingMetadata(at: cursor.current, name: path.leaf),
              current.identity == identity else { return }
        _ = unlinkat(cursor.current, path.leaf, AT_REMOVEDIR)
    }

    private static func openOwnedParent(
        _ components: ArraySlice<String>,
        rootFD: Int32,
        directories: [String: LeonardoFileIdentity]
    ) throws -> DirectoryCursor {
        var current = rootFD
        var opened: [Int32] = []
        var prefix: [String] = []
        do {
            for component in components {
                prefix.append(component)
                let key = prefix.joined(separator: "/")
                guard let expected = directories[key],
                      let actual = try metadata(at: current, name: component),
                      actual.identity == expected,
                      actual.isDirectory,
                      !actual.isSymbolicLink else {
                    throw LeonardoSecureExtractionFailure.identityChanged
                }
                let descriptor = try openDirectoryComponent(current, component)
                guard try metadata(of: descriptor).identity == expected else {
                    Darwin.close(descriptor)
                    throw LeonardoSecureExtractionFailure.identityChanged
                }
                opened.append(descriptor)
                current = descriptor
            }
            return DirectoryCursor(current: current, opened: opened)
        } catch {
            for descriptor in opened.reversed() { Darwin.close(descriptor) }
            throw error
        }
    }

    private static func deeperPathFirst(_ left: String, _ right: String) -> Bool {
        let leftDepth = left.split(separator: "/").count
        let rightDepth = right.split(separator: "/").count
        return leftDepth == rightDepth ? left > right : leftDepth > rightDepth
    }

    private struct CleanupFrame {
        let fd: Int32
        let parentFD: Int32?
        let nameInParent: String?
        let identity: LeonardoFileIdentity?
        var names: [String]
        var next: Int
        let depth: Int
    }

    private static func removeDirectoryContents(_ rootFD: Int32) {
        guard let names = try? directoryNames(rootFD) else { return }
        var stack = [CleanupFrame(fd: rootFD, parentFD: nil, nameInParent: nil, identity: nil, names: names, next: 0, depth: 0)]
        while !stack.isEmpty {
            let index = stack.count - 1
            if stack[index].next == stack[index].names.count {
                let frame = stack.removeLast()
                if let parentFD = frame.parentFD, let name = frame.nameInParent, let identity = frame.identity,
                   let current = existingMetadata(at: parentFD, name: name), current.identity == identity {
                    _ = unlinkat(parentFD, name, AT_REMOVEDIR)
                }
                if frame.fd != rootFD { Darwin.close(frame.fd) }
                continue
            }

            let name = stack[index].names[stack[index].next]
            stack[index].next += 1
            guard let entry = existingMetadata(at: stack[index].fd, name: name) else { continue }
            if entry.isDirectory && !entry.isSymbolicLink {
                guard stack[index].depth + 1 < maximumPathComponents else { continue }
                guard let descriptor = try? openDirectoryComponent(stack[index].fd, name) else {
                    continue
                }
                guard (try? metadata(of: descriptor).identity) == entry.identity else {
                    Darwin.close(descriptor)
                    continue
                }
                guard let names = try? directoryNames(descriptor) else {
                    Darwin.close(descriptor)
                    continue
                }
                stack.append(CleanupFrame(
                    fd: descriptor,
                    parentFD: stack[index].fd,
                    nameInParent: name,
                    identity: entry.identity,
                    names: names,
                    next: 0,
                    depth: stack[index].depth + 1
                ))
            } else if let current = existingMetadata(at: stack[index].fd, name: name), current.identity == entry.identity {
                _ = unlinkat(stack[index].fd, name, 0)
            }
        }
    }

    private static func directoryNames(_ descriptor: Int32) throws -> [String] {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else {
            throw LeonardoSecureExtractionFailure.systemCall("duplicate directory", errno)
        }
        guard let directory = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw LeonardoSecureExtractionFailure.systemCall("open directory stream", errno)
        }
        defer { closedir(directory) }
        var names: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: entry.pointee.d_name)) {
                    String(validatingUTF8: $0)
                }
            }
            if let name, name != ".", name != ".." { names.append(name) }
        }
        return names
    }

    private static var directoryFlags: Int32 {
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    }
}
#else
enum LeonardoSecureExtraction {
    static let maximumPathComponents = LeonardoZIPArchive.maximumPathComponents

    static func extract(
        entries: [LeonardoZIPArchive.Entry],
        to destination: URL,
        hooks: LeonardoSecureExtractionHooks?
    ) throws -> LeonardoExtractionOwnership {
        throw LeonardoSecureExtractionFailure.unsupported
    }

    static func verifyWorkspace(at directoryURL: URL, ownership: LeonardoExtractionOwnership) throws {
        throw LeonardoSecureExtractionFailure.unsupported
    }

    static func removeOwnedTemporaryWorkspace(at directoryURL: URL, ownership: LeonardoExtractionOwnership) {}
}
#endif
