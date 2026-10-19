import Foundation
import Testing
@testable import LeonardoCore

struct LeonardoSecureExtractionTests {
    private let manager = FileManager.default

    @Test func directoryAmplificationAndAliasesAreRejectedBeforeExtraction() throws {
        let suffix = Array(repeating: "d", count: 61)
        var entries = [LeonardoZIPArchive.Entry(name: "document.mdlf", data: Data())]
        for index in 0..<34 {
            let name = (["assets", "x"] + suffix + [String(format: "f%02d", index)]).joined(separator: "/")
            entries.append(.init(name: name, data: Data()))
        }
        var bytes = try LeonardoZIPArchive.write(entries)
        let distinct = Array("0123456789abcdefghijklmnopqrstuvwx")
        for index in 0..<34 {
            let old = Data(entries[index + 1].name.utf8)
            let new = Data(entries[index + 1].name.replacingOccurrences(of: "assets/x/", with: "assets/\(distinct[index])/").utf8)
            var start = 0
            while let range = bytes.range(of: old, options: [], in: start..<bytes.count) {
                bytes.replaceSubrange(range, with: new)
                start = range.upperBound
            }
            entries[index + 1] = .init(name: String(decoding: new, as: UTF8.self), data: Data())
        }
        #expect(throws: LeonardoPackageError.self) { try LeonardoZIPArchive.read(bytes) }
        #expect(throws: LeonardoPackageError.self) { try LeonardoZIPArchive.write(entries) }
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.write([
                .init(name: "assets/A/first", data: Data()),
                .init(name: "assets/a/second", data: Data())
            ])
        }
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.write([
                .init(name: "assets/é/first", data: Data()),
                .init(name: "assets/e\u{301}/second", data: Data())
            ])
        }
    }

    @Test func finalVerificationRejectsRetargetedChildAndDestinationParent() throws {
        for target in ["child", "parent"] {
            let root = try temporary()
            defer { try? manager.removeItem(at: root) }
            let parent = root.appendingPathComponent("parent")
            let outside = root.appendingPathComponent("outside")
            try manager.createDirectory(at: parent, withIntermediateDirectories: false)
            try manager.createDirectory(at: outside, withIntermediateDirectories: false)
            let destination = parent.appendingPathComponent("destination")
            let package = try archive(in: root, assetName: "assets/data")
            let hooks = LeonardoSecureExtractionHooks(beforeReturn: {
                let path = target == "child" ? destination.appendingPathComponent("assets") : parent
                let moved = target == "child" ? destination.appendingPathComponent("owned-assets") : root.appendingPathComponent("owned-parent")
                try manager.moveItem(at: path, to: moved)
                try manager.createSymbolicLink(at: path, withDestinationURL: outside)
            })
            #expect(throws: LeonardoPackageError.self) {
                try LeonardoPackageTransport.openForTesting(package, extractingTo: destination, hooks: hooks)
            }
            #expect(try manager.contentsOfDirectory(atPath: outside.path).isEmpty)
            let link = target == "child" ? destination.appendingPathComponent("assets") : parent
            try assertSymbolicLink(at: link, targeting: outside)
        }
    }

    @Test func zipMemberDepthIsBoundTo64Components() {
        let valid = (0..<64).map { "part\($0)" }.joined(separator: "/")
        let invalid = (0..<65).map { "part\($0)" }.joined(separator: "/")

        #expect(LeonardoZIPArchive.safePath(valid))
        #expect(!LeonardoZIPArchive.safePath(invalid))
        #expect(!LeonardoZIPArchive.safePath(invalid + "/"))
        #expect(throws: LeonardoPackageError.self) {
            try LeonardoZIPArchive.write([
                .init(name: "document.mdlf", data: Data("document".utf8)),
                .init(name: invalid, data: Data("asset".utf8))
            ])
        }
    }

    @Test func existingDestinationEntriesAreNeverReplaced() throws {
        for kind in ["file", "symlink", "directory"] {
            let root = try temporary()
            defer { try? manager.removeItem(at: root) }
            let package = try archive(in: root)
            let destination = root.appendingPathComponent("destination")
            let outside = root.appendingPathComponent("outside")
            try manager.createDirectory(at: outside, withIntermediateDirectories: false)
            try install(kind, at: destination, outside: outside)

            #expect(throws: LeonardoPackageError.self) {
                try LeonardoPackageTransport.open(package, extractingTo: destination)
            }
            try assertUnchanged(kind, at: destination, outside: outside)
        }
    }

    @Test func atomicRootClaimPreservesCompetingEntries() throws {
        for kind in ["file", "symlink", "directory"] {
            let root = try temporary()
            defer { try? manager.removeItem(at: root) }
            let package = try archive(in: root)
            let destination = root.appendingPathComponent("destination")
            let outside = root.appendingPathComponent("outside")
            try manager.createDirectory(at: outside, withIntermediateDirectories: false)
            let hooks = LeonardoSecureExtractionHooks(beforeRootClaim: {
                try install(kind, at: destination, outside: outside)
            })

            #expect(throws: LeonardoPackageError.self) {
                try LeonardoPackageTransport.openForTesting(package, extractingTo: destination, hooks: hooks)
            }
            try assertUnchanged(kind, at: destination, outside: outside)
        }
    }

    @Test func userSymlinkParentIsRejectedWithoutFollowingIt() throws {
        let root = try temporary()
        defer { try? manager.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside")
        let linked = root.appendingPathComponent("linked")
        try manager.createDirectory(at: outside, withIntermediateDirectories: false)
        try manager.createSymbolicLink(at: linked, withDestinationURL: outside)
        let package = try archive(in: root)

        #expect(throws: LeonardoPackageError.self) {
            try LeonardoPackageTransport.open(package, extractingTo: linked.appendingPathComponent("destination"))
        }
        #expect(!manager.fileExists(atPath: outside.appendingPathComponent("destination").path))
        try assertSymbolicLink(at: linked, targeting: outside)
    }

    @Test func parentRetargetRaceFailsClosedAndPreservesTheReplacement() throws {
        let root = try temporary()
        defer { try? manager.removeItem(at: root) }
        let parent = root.appendingPathComponent("parent")
        let outside = root.appendingPathComponent("outside")
        let destination = parent.appendingPathComponent("destination")
        try manager.createDirectory(at: parent, withIntermediateDirectories: false)
        try manager.createDirectory(at: outside, withIntermediateDirectories: false)
        let package = try archive(in: root)
        let hooks = LeonardoSecureExtractionHooks(beforeRootClaim: {
            try manager.removeItem(at: parent)
            try manager.createSymbolicLink(at: parent, withDestinationURL: outside)
        })

        #expect(throws: LeonardoPackageError.self) {
            try LeonardoPackageTransport.openForTesting(package, extractingTo: destination, hooks: hooks)
        }
        try assertSymbolicLink(at: parent, targeting: outside)
        #expect(!manager.fileExists(atPath: outside.appendingPathComponent("destination").path))
    }

    @Test func competingEntryInsideClaimedRootSurvivesFailureCleanup() throws {
        for kind in ["file", "symlink", "directory"] {
            let root = try temporary()
            defer { try? manager.removeItem(at: root) }
            let package = try archive(in: root, documentName: "a.mdlf", assetName: "assets/z")
            let destination = root.appendingPathComponent("destination")
            let outside = root.appendingPathComponent("outside")
            try manager.createDirectory(at: outside, withIntermediateDirectories: false)
            let competing = destination.appendingPathComponent("a.mdlf")
            let hooks = LeonardoSecureExtractionHooks(afterRootClaim: {
                try install(kind, at: competing, outside: outside)
            })

            #expect(throws: LeonardoPackageError.self) {
                try LeonardoPackageTransport.openForTesting(package, extractingTo: destination, hooks: hooks)
            }
            try assertUnchanged(kind, at: competing, outside: outside)
            #expect(manager.fileExists(atPath: destination.path))
        }
    }

    @Test func failureCleanupRemovesOnlyKnownEntries() throws {
        let root = try temporary()
        defer { try? manager.removeItem(at: root) }
        let package = try archive(in: root, documentName: "a.mdlf", assetName: "assets/z")
        let destination = root.appendingPathComponent("destination")
        let foreign = destination.appendingPathComponent("foreign.txt")
        let competing = destination.appendingPathComponent("assets/z")
        let hooks = LeonardoSecureExtractionHooks(beforeFileClaim: { name in
            guard name == "assets/z" else { return }
            try Data("foreign".utf8).write(to: foreign)
            try Data("competing".utf8).write(to: competing)
        })

        #expect(throws: LeonardoPackageError.self) {
            try LeonardoPackageTransport.openForTesting(package, extractingTo: destination, hooks: hooks)
        }
        #expect(manager.fileExists(atPath: foreign.path))
        #expect(try String(contentsOf: competing, encoding: .utf8) == "competing")
        #expect(!manager.fileExists(atPath: destination.appendingPathComponent("a.mdlf").path))
    }

    @Test func discardDoesNotRemoveAReplacementRoot() throws {
        let root = try temporary()
        defer { try? manager.removeItem(at: root) }
        let package = try archive(in: root)
        let workspace = try LeonardoPackageTransport.open(package)
        let owned = workspace.directoryURL
        let replacement = root.appendingPathComponent("owned-original")
        try manager.moveItem(at: owned, to: replacement)
        try manager.createDirectory(at: owned, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: owned.appendingPathComponent("keep.txt"))

        LeonardoPackageTransport.discard(workspace)

        #expect(manager.fileExists(atPath: owned.appendingPathComponent("keep.txt").path))
        try manager.removeItem(at: replacement)
    }

    @Test func discardRemovesTheOwnedTemporaryWorkspace() throws {
        let root = try temporary()
        defer { try? manager.removeItem(at: root) }
        let workspace = try LeonardoPackageTransport.open(try archive(in: root))
        let directory = workspace.directoryURL
        #expect(manager.fileExists(atPath: directory.path))

        LeonardoPackageTransport.discard(workspace)

        #expect(!manager.fileExists(atPath: directory.path))
    }

    @Test func macOSSystemTemporaryAliasesRemainUsable() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("LeonardoSecure-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let destination = root.appendingPathComponent("destination", isDirectory: true)

        let workspace = try LeonardoPackageTransport.open(
            try archive(in: root),
            extractingTo: destination
        )
        #expect(manager.fileExists(atPath: workspace.documentURL.path))
        LeonardoPackageTransport.discard(workspace)
        #expect(manager.fileExists(atPath: destination.path))
    }

    @Test func invalidRootDocumentDoesNotClaimDestination() throws {
        let root = try temporary()
        defer { try? manager.removeItem(at: root) }
        let package = root.appendingPathComponent("invalid.mdlz")
        let invalid = LeonardoZIPArchive.Entry(name: "document.mdlf", data: Data("not MDLF".utf8))
        try LeonardoZIPArchive.write([invalid]).write(to: package)
        let destination = root.appendingPathComponent("destination")

        #expect(throws: LeonardoFormatError.self) {
            try LeonardoPackageTransport.open(package, extractingTo: destination)
        }
        #expect(!manager.fileExists(atPath: destination.path))
    }

    private func temporary() throws -> URL {
        let url = manager.temporaryDirectory.appendingPathComponent("LeonardoSecure-\(UUID().uuidString)")
        try manager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func archive(
        in root: URL,
        documentName: String = "document.mdlf",
        assetName: String? = nil
    ) throws -> URL {
        var entries = [LeonardoZIPArchive.Entry(
            name: documentName,
            data: Data(try LeonardoFormatParser.serialize(LeonardoDocument(body: "# Document")).utf8)
        )]
        if let assetName {
            entries.append(.init(name: assetName, data: Data("asset".utf8)))
        }
        let package = root.appendingPathComponent("package.mdlz")
        try LeonardoZIPArchive.write(entries).write(to: package)
        return package
    }

    private func install(_ kind: String, at destination: URL, outside: URL) throws {
        switch kind {
        case "file":
            try Data("keep".utf8).write(to: destination)
        case "symlink":
            try manager.createSymbolicLink(at: destination, withDestinationURL: outside)
        case "directory":
            try manager.createDirectory(at: destination, withIntermediateDirectories: false)
            try Data("keep".utf8).write(to: destination.appendingPathComponent("keep.txt"))
        default:
            Issue.record("Unknown destination fixture: \(kind)")
        }
    }

    private func assertUnchanged(_ kind: String, at destination: URL, outside: URL) throws {
        switch kind {
        case "file":
            #expect(try String(contentsOf: destination, encoding: .utf8) == "keep")
        case "symlink":
            try assertSymbolicLink(at: destination, targeting: outside)
            #expect(!manager.fileExists(atPath: outside.appendingPathComponent("document.mdlf").path))
        case "directory":
            #expect(try String(contentsOf: destination.appendingPathComponent("keep.txt"), encoding: .utf8) == "keep")
        default:
            Issue.record("Unknown destination fixture: \(kind)")
        }
    }

    private func assertSymbolicLink(at link: URL, targeting destination: URL) throws {
        let actual = try manager.destinationOfSymbolicLink(atPath: link.path)
        #expect(actual == destination.path || actual == destination.lastPathComponent)
    }
}
