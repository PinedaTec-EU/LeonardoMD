#if os(macOS)
import Foundation
import XCTest
@testable import LeonardoCore

final class TrashUnavailableTests: XCTestCase {
    func testPreflightDistinguishesUnsupportedFromMissingAndInaccessibleTrash() async throws {
        let fixture = try TemporaryDirectory()
        try "keep".write(to: fixture.url.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        let project = ProjectDescriptor(name: "Test", rootURL: fixture.url)
        let cases: [(NSError?, TrashAvailability)] = [
            (nil, .available), (CocoaError(.featureUnsupported) as NSError, .unavailable),
            (NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTSUP)), .unavailable),
            (CocoaError(.fileNoSuchFile) as NSError, .unknown),
            (CocoaError(.fileWriteNoPermission) as NSError, .unknown),
            (CocoaError(.fileWriteVolumeReadOnly) as NSError, .unknown)
        ]
        for (error, expected) in cases {
            let repository = LocalProjectRepository(fileManager: UnavailableTrashManager(error: error))
            let availability = try await repository.trashAvailability("note.md", in: project)
            XCTAssertEqual(availability, expected)
            XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent("note.md").path))
        }
    }

    func testUnsupportedTrashPreservesItemUntilExplicitPermanentDeletion() async throws {
        let fixture = try TemporaryDirectory()
        let repository = LocalProjectRepository(fileManager: UnavailableTrashManager(error: CocoaError(.featureUnsupported) as NSError))
        let project = ProjectDescriptor(name: "Test", rootURL: fixture.url)
        for name in ["note.md", "folder"] {
            let target = fixture.url.appendingPathComponent(name)
            if name == "folder" {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                try "keep".write(to: target.appendingPathComponent("nested.md"), atomically: true, encoding: .utf8)
            } else { try "keep".write(to: target, atomically: true, encoding: .utf8) }
            do {
                try await repository.delete(name, in: project)
                XCTFail("Unsupported Trash must not delete")
            } catch FileDeletionError.trashUnavailable { }
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
            try await repository.delete(name, in: project, mode: .permanentlyConfirmed)
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        }
    }

    func testPermanentDeletionRetainsRootContainmentAndSymlinkGuards() async throws {
        let fixture = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let project = ProjectDescriptor(name: "Test", rootURL: fixture.url)
        let protected = outside.url.appendingPathComponent("note.md")
        try "keep".write(to: protected, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: fixture.url.appendingPathComponent("alias"), withDestinationURL: outside.url)
        for path in ["", "../note.md", "alias/note.md"] {
            do {
                try await repository.delete(path, in: project, mode: .permanentlyConfirmed)
                XCTFail("Unsafe target accepted: \(path)")
            } catch { }
        }
        XCTAssertEqual(try String(contentsOf: protected, encoding: .utf8), "keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.url.path))
    }
}

private final class UnavailableTrashManager: FileManager {
    let error: NSError?
    init(error: NSError?) { self.error = error; super.init() }
    override func url(for directory: SearchPathDirectory, in domain: SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        if directory == .trashDirectory {
            XCTAssertFalse(shouldCreate)
            if let error { throw error }
            return URL(fileURLWithPath: "/unused-trash")
        }
        return try super.url(for: directory, in: domain, appropriateFor: url, create: shouldCreate)
    }
    override func trashItem(at url: URL, resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        throw error ?? CocoaError(.featureUnsupported) as NSError
    }
}
#endif
