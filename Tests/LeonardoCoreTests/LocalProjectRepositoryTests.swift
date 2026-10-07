import Foundation
import XCTest
@testable import LeonardoCore

final class LocalProjectRepositoryTests: XCTestCase {
    func testProjectTreeOperationsAndSearch() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)

        let docs = try await repository.createFolder(named: "docs", in: project)
        _ = try await repository.createMarkdown(
            named: "readme",
            in: project,
            at: docs.relativePath,
            contents: "# Needle\nA searchable note."
        )
        _ = try await repository.createFolder(named: ".private", in: project)
        let gitDirectory = try await repository.createFolder(named: ".git", in: project)
        _ = try await repository.createMarkdown(named: "ignored", in: project, at: gitDirectory.relativePath, contents: "Needle")

        let visible = try await repository.children(of: "", in: project)
        XCTAssertEqual(visible.map(\.name), ["docs"])
        let hidden = try await repository.children(of: "", in: project, showHidden: true)
        XCTAssertEqual(Set(hidden.map(\.name)), [".git", ".leonardomd", ".private", "docs"])

        let matches = try await repository.search(in: project, query: "needle")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.relativePath, "docs/readme.md")
        XCTAssertEqual(matches.first?.lineNumber, 1)
        let hiddenSearch = try await repository.search(in: project, query: "needle", showHidden: true)
        XCTAssertTrue(hiddenSearch.allSatisfy { !$0.relativePath.hasPrefix(".git/") })

        _ = try await repository.rename("docs/readme.md", in: project, to: "renamed.md")
        _ = try await repository.move("docs/renamed.md", in: project, to: "")
        let movedChildren = try await repository.children(of: "", in: project).map(\.name)
        XCTAssertEqual(movedChildren, ["docs", "renamed.md"])
        try await repository.delete("renamed.md", in: project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.rootURL.appendingPathComponent("renamed.md").path))
    }

    func testPathSafetyRejectsEscapeAndDescendantMoves() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)
        _ = try await repository.createFolder(named: "docs", in: project)

        do {
            _ = try await repository.children(of: "../outside", in: project)
            XCTFail("Expected path escape to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            _ = try await repository.move("docs", in: project, to: "docs")
            XCTFail("Expected descendant move to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .cannotMoveIntoDescendant)
        }
    }

    func testProjectRenameMoveAndDeleteOperateOnWorkspaceFolders() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let destinationWorkspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Archive"))
        let project = try await repository.createProject(named: "Notes", in: workspace)

        let renamed = try await repository.renameProject(project, to: "Renamed", in: workspace)
        let moved = try await repository.moveProject(renamed, to: destinationWorkspace)
        XCTAssertEqual(moved.name, "Renamed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.rootURL.path))

        try await repository.deleteProject(moved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.rootURL.path))
    }

    func testSearchStreamYieldsPartialBatchesAndIgnoresGit() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)
        _ = try await repository.createMarkdown(named: "a.md", in: project, contents: "needle in A")
        _ = try await repository.createMarkdown(named: "b.md", in: project, contents: "needle in B")
        let gitDirectory = try await repository.createFolder(named: ".git", in: project)
        _ = try await repository.createMarkdown(
            named: "ignored.md",
            in: project,
            at: gitDirectory.relativePath,
            contents: "needle in ignored"
        )

        let stream = await repository.searchStream(in: project, query: "needle", showHidden: true)
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        let second = try await iterator.next()
        XCTAssertEqual(first?.count, 1)
        XCTAssertEqual(second?.count, 1)
        XCTAssertEqual(Set([first, second].compactMap { $0 }.flatMap { $0 }.map(\.relativePath)), ["a.md", "b.md"])
        let third = try await iterator.next()
        XCTAssertNil(third)
    }

    func testSearchStreamCancellationStopsConsumerAndProducer() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)
        for index in 0..<1_000 {
            let url = project.rootURL.appendingPathComponent("note-\(index).md")
            try Data("needle".utf8).write(to: url, options: [.atomic])
        }

        let stream = await repository.searchStream(in: project, query: "needle")
        let firstBatchReceived = SearchStreamSignal()
        let consumer = Task { () throws -> Int in
            var iterator = stream.makeAsyncIterator()
            guard let first = try await iterator.next() else { return 0 }
            await firstBatchReceived.signal()
            try await Task.sleep(nanoseconds: 60_000_000_000)
            var count = first.count
            while let batch = try await iterator.next() {
                count += batch.count
            }
            return count
        }

        await firstBatchReceived.wait()
        consumer.cancel()
        let result = await consumer.result
        guard case .failure = result else {
            XCTFail("Cancelling the stream consumer should stop its task")
            return
        }
    }
}

private actor SearchStreamSignal {
    private var signaled = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }

    func signal() {
        signaled = true
        waiter?.resume()
        waiter = nil
    }
}
