#if os(macOS)
import Foundation
import XCTest
@testable import LeonardoCore

final class TrashDeletionTests: XCTestCase {
    func testFilesFoldersAndProjectsRemainRecoverableFromTrash() async throws {
        for kind in ["file", "folder", "project"] {
            try await verifyDeletion(kind: kind, rejectTrash: false)
        }
    }

    func testTrashFailurePreservesFilesFoldersAndProjects() async throws {
        for kind in ["file", "folder", "project"] {
            try await verifyDeletion(kind: kind, rejectTrash: true)
        }
    }

    private func verifyDeletion(kind: String, rejectTrash: Bool) async throws {
        let fixture = try TemporaryDirectory()
        let observation = TrashObservation()
        let repository = LocalProjectRepository(fileManager: ObservedTrashFileManager(
            observation: observation, rejectTrash: rejectTrash))
        let workspace = try await repository.createWorkspace(at: fixture.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: UUID().uuidString, in: workspace)
        let target: URL
        if kind == "file" {
            target = try await repository.createMarkdown(named: "note", in: project, contents: "Keep me").url
        } else {
            target = kind == "project" ? project.rootURL : try await repository.createFolder(named: "docs", in: project).url
            try "Keep me".write(to: target.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)
        }
        defer {
            if let trashed = observation.snapshot.url { try? FileManager.default.removeItem(at: trashed) }
        }
        do {
            if kind == "project" { try await repository.deleteProject(project) }
            else { try await repository.delete(kind == "file" ? "note.md" : "docs", in: project) }
            if rejectTrash { XCTFail("Trash failure must propagate: \(kind)") }
        } catch {
            guard rejectTrash else { throw error }
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteNoPermission.rawValue)
        }
        XCTAssertEqual(observation.snapshot.attempts, 1, kind)
        if !rejectTrash {
            XCTAssertFalse(FileManager.default.fileExists(atPath: target.path), kind)
            let trashed = try XCTUnwrap(observation.snapshot.url, kind)
            let contentURL = kind == "file" ? trashed : trashed.appendingPathComponent("note.md")
            XCTAssertEqual(try String(contentsOf: contentURL, encoding: .utf8), "Keep me", kind)
            // Restore Foundation's actual Trash item, including nested contents.
            try FileManager.default.moveItem(at: trashed, to: target)
        }
        let contentURL = kind == "file" ? target : target.appendingPathComponent("note.md")
        XCTAssertEqual(try String(contentsOf: contentURL, encoding: .utf8), "Keep me", kind)
    }
}

private final class TrashObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?
    private var attempts = 0

    var snapshot: (url: URL?, attempts: Int) { lock.withLock { (url, attempts) } }
    func attempted() { lock.withLock { attempts += 1 } }
    func moved(to result: URL?) { lock.withLock { url = result } }
}

private final class ObservedTrashFileManager: FileManager {
    private let observation: TrashObservation
    private let rejectTrash: Bool

    init(observation: TrashObservation, rejectTrash: Bool) {
        self.observation = observation
        self.rejectTrash = rejectTrash
        super.init()
    }

    override func trashItem(at url: URL, resultingItemURL outResultingURL: AutoreleasingUnsafeMutablePointer<NSURL?>?) throws {
        observation.attempted()
        if rejectTrash { throw CocoaError(.fileWriteNoPermission) }
        var result: NSURL?
        try super.trashItem(at: url, resultingItemURL: &result)
        observation.moved(to: result as URL?)
        outResultingURL?.pointee = result
    }
}
#endif
