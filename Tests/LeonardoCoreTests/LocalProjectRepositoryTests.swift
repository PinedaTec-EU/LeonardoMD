import Foundation
import XCTest
@testable import LeonardoCore

final class LocalProjectRepositoryTests: XCTestCase {
    func testProjectThroughTmpAliasEnumeratesAndMutatesCanonicalChildren() async throws {
        let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("leonardo-alias-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = LocalProjectRepository()
        let project = try await repository.project(at: root)
        let folder = try await repository.createFolder(named: "docs", in: project)
        let document = try await repository.createMarkdown(named: "note", in: project, at: "docs", contents: "alias token")
        let panelRoot = try XCTUnwrap(URL(string: "file:///private" + root.path + "/"))
        let children = try await repository.children(of: panelRoot, in: panelRoot)
        XCTAssertEqual(children.map(\.relativePath), ["docs"])
        let nested = try await repository.children(of: panelRoot.appendingPathComponent("docs"), in: root)
        XCTAssertEqual(nested.map(\.relativePath), ["docs/note.md"])
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folder.url)
        let aliasTraversal = try XCTUnwrap(URL(string: panelRoot.absoluteString + "alias/../docs/"))
        do {
            _ = try await repository.children(of: aliasTraversal, in: panelRoot)
            XCTFail("Normalization must not hide a symlink component")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        let matches = try await repository.search(in: project, query: "token")
        XCTAssertEqual(matches.map(\.relativePath), ["docs/note.md"])
        let renamed = try await repository.rename(document.relativePath, in: project, to: "renamed.md")
        XCTAssertEqual(renamed.relativePath, "docs/renamed.md")
        try await repository.delete(renamed.relativePath, in: project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.url.path))
    }

    func testChildrenOmitSymlinkEntriesAndRejectSymlinkDirectories() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)

        let internalDirectory = project.rootURL.appendingPathComponent("internal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDirectory, withIntermediateDirectories: true)
        let internalFile = project.rootURL.appendingPathComponent("inside.md")
        try Data("inside".utf8).write(to: internalFile)

        let outsideDirectory = directory.url.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let outsideFile = outsideDirectory.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outsideFile)

        let danglingTarget = directory.url.appendingPathComponent("missing.md")
        let aliases = [
            ("internal-file-alias", internalFile),
            ("outside-file-alias", outsideFile),
            ("internal-directory-alias", internalDirectory),
            ("outside-directory-alias", outsideDirectory),
            ("dangling-alias", danglingTarget)
        ]
        for (name, target) in aliases {
            try FileManager.default.createSymbolicLink(
                at: project.rootURL.appendingPathComponent(name),
                withDestinationURL: target
            )
        }

        let nodes = try await repository.children(of: "", in: project, showHidden: true)
        let nodeNames = Set(nodes.map(\.name))
        XCTAssertTrue(nodeNames.contains("inside.md"))
        XCTAssertTrue(nodeNames.contains("internal"))
        XCTAssertTrue(nodeNames.isDisjoint(with: Set(aliases.map(\.0))))

        for alias in aliases {
            do {
                _ = try await repository.children(of: alias.0, in: project)
                XCTFail("Expected symlink directory resolution to be rejected for \(alias.0)")
            } catch let error as FileSystemRepositoryError {
                XCTAssertEqual(error, .pathEscapesProject)
            }
        }

        do {
            _ = try await repository.children(
                of: project.rootURL.appendingPathComponent("internal-directory-alias"),
                in: project.rootURL
            )
            XCTFail("Expected URL symlink resolution to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        XCTAssertEqual(try String(contentsOf: internalFile, encoding: .utf8), "inside")
        XCTAssertEqual(try String(contentsOf: outsideFile, encoding: .utf8), "outside")
    }

    func testSearchAndSearchStreamSkipInternalOutsideAndDanglingSymlinks() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)
        let token = "symlink-search-token"

        let inside = project.rootURL.appendingPathComponent("inside.md")
        try Data("regular \(token)".utf8).write(to: inside)
        let internalTarget = project.rootURL.appendingPathComponent("target.md")
        try Data("internal target \(token)".utf8).write(to: internalTarget)
        let internalDirectory = project.rootURL.appendingPathComponent("internal", isDirectory: true)
        try FileManager.default.createDirectory(at: internalDirectory, withIntermediateDirectories: true)
        let nestedTarget = internalDirectory.appendingPathComponent("nested.md")
        try Data("nested \(token)".utf8).write(to: nestedTarget)

        let outsideDirectory = directory.url.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let outsideFile = outsideDirectory.appendingPathComponent("outside.md")
        try Data("outside \(token)".utf8).write(to: outsideFile)
        let outsideNested = outsideDirectory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideNested, withIntermediateDirectories: true)
        let outsideNestedFile = outsideNested.appendingPathComponent("outside-nested.md")
        try Data("outside nested \(token)".utf8).write(to: outsideNestedFile)

        try FileManager.default.createSymbolicLink(
            at: project.rootURL.appendingPathComponent("internal-alias.md"),
            withDestinationURL: internalTarget
        )
        try FileManager.default.createSymbolicLink(
            at: project.rootURL.appendingPathComponent("outside-alias.md"),
            withDestinationURL: outsideFile
        )
        try FileManager.default.createSymbolicLink(
            at: project.rootURL.appendingPathComponent("internal-directory-alias"),
            withDestinationURL: internalDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: project.rootURL.appendingPathComponent("outside-directory-alias"),
            withDestinationURL: outsideDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: project.rootURL.appendingPathComponent("dangling-alias.md"),
            withDestinationURL: directory.url.appendingPathComponent("missing.md")
        )

        let directMatches = try await repository.search(in: project, query: token, showHidden: true)
        XCTAssertEqual(Set(directMatches.map(\.relativePath)), ["inside.md", "internal/nested.md", "target.md"])
        XCTAssertTrue(directMatches.allSatisfy { $0.url.path.hasPrefix(project.rootURL.path + "/") })

        let stream = await repository.searchStream(in: project, query: token, showHidden: true)
        var streamedMatches: [SearchMatch] = []
        for try await batch in stream {
            streamedMatches.append(contentsOf: batch)
        }
        XCTAssertEqual(Set(streamedMatches.map(\.relativePath)), Set(directMatches.map(\.relativePath)))
        XCTAssertTrue(streamedMatches.allSatisfy { $0.url.path.hasPrefix(project.rootURL.path + "/") })
        XCTAssertEqual(try String(contentsOf: outsideFile, encoding: .utf8), "outside \(token)")
        XCTAssertEqual(try String(contentsOf: outsideNestedFile, encoding: .utf8), "outside nested \(token)")
    }

    func testDeleteRenameAndMoveRejectSymlinkEntriesAndPreserveTargets() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)

        let internalTarget = project.rootURL.appendingPathComponent("target.md")
        try Data("target".utf8).write(to: internalTarget)
        let internalAlias = project.rootURL.appendingPathComponent("alias.md")
        try FileManager.default.createSymbolicLink(at: internalAlias, withDestinationURL: internalTarget)

        do {
            try await repository.delete("alias.md", in: project)
            XCTFail("Expected deleting a symlink entry to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            _ = try await repository.rename("alias.md", in: project, to: "renamed.md")
            XCTFail("Expected renaming a symlink entry to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            _ = try await repository.move("alias.md", in: project, to: "")
            XCTFail("Expected moving a symlink entry to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: internalAlias.path))
        XCTAssertEqual(try String(contentsOf: internalTarget, encoding: .utf8), "target")

        let outsideTarget = directory.url.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outsideTarget)
        let outsideAlias = project.rootURL.appendingPathComponent("outside-alias.md")
        try FileManager.default.createSymbolicLink(at: outsideAlias, withDestinationURL: outsideTarget)
        do {
            try await repository.delete("outside-alias.md", in: project)
            XCTFail("Expected deleting an outside symlink entry to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            _ = try await repository.rename("outside-alias.md", in: project, to: "outside-renamed.md")
            XCTFail("Expected renaming an outside symlink entry to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            _ = try await repository.move("outside-alias.md", in: project, to: "")
            XCTFail("Expected moving an outside symlink entry to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideAlias.path))
        XCTAssertEqual(try String(contentsOf: outsideTarget, encoding: .utf8), "outside")
    }

    func testCreationRejectsDanglingSymlinkDestinations() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)
        let missingTarget = directory.url.appendingPathComponent("missing-target")
        let projectAlias = workspace.appendingPathComponent("Alias")
        let folderAlias = project.rootURL.appendingPathComponent("folder")
        let fileAlias = project.rootURL.appendingPathComponent("note.md")
        for alias in [projectAlias, folderAlias, fileAlias] {
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: missingTarget)
        }
        do {
            _ = try await repository.createProject(named: "Alias", in: workspace)
            XCTFail("Expected project alias rejection")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            _ = try await repository.createFolder(named: "folder", in: project)
            XCTFail("Expected folder alias rejection")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            _ = try await repository.createMarkdown(named: "note.md", in: project, contents: "replacement")
            XCTFail("Expected file alias rejection")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        for alias in [projectAlias, folderAlias, fileAlias] {
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path), missingTarget.path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingTarget.path))
    }

    func testDestructiveOperationsRejectSymlinkParentsAndDanglingLinks() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)

        let realParent = project.rootURL.appendingPathComponent("real-parent", isDirectory: true)
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: true)
        let internalParentAlias = project.rootURL.appendingPathComponent("internal-parent-alias")
        try FileManager.default.createSymbolicLink(at: internalParentAlias, withDestinationURL: realParent)
        let source = project.rootURL.appendingPathComponent("source.md")
        try Data("source".utf8).write(to: source)

        do {
            _ = try await repository.move("source.md", in: project, to: "internal-parent-alias")
            XCTFail("Expected moving through an internal symlink parent to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: realParent.appendingPathComponent("source.md").path))

        let outsideParent = directory.url.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideParent, withIntermediateDirectories: true)
        let outsideParentAlias = project.rootURL.appendingPathComponent("outside-parent-alias")
        try FileManager.default.createSymbolicLink(at: outsideParentAlias, withDestinationURL: outsideParent)
        do {
            _ = try await repository.move("source.md", in: project, to: "outside-parent-alias")
            XCTFail("Expected moving through an outside symlink parent to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outsideParent.appendingPathComponent("source.md").path))

        let danglingParentAlias = project.rootURL.appendingPathComponent("dangling-parent-alias")
        try FileManager.default.createSymbolicLink(
            at: danglingParentAlias,
            withDestinationURL: directory.url.appendingPathComponent("missing-parent", isDirectory: true)
        )
        do {
            _ = try await repository.move("source.md", in: project, to: "dangling-parent-alias")
            XCTFail("Expected moving through a dangling symlink parent to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }

        let dangling = project.rootURL.appendingPathComponent("dangling.md")
        try FileManager.default.createSymbolicLink(
            at: dangling,
            withDestinationURL: directory.url.appendingPathComponent("missing.md")
        )
        for operation in ["delete", "rename", "move"] {
            do {
                switch operation {
                case "delete":
                    try await repository.delete("dangling.md", in: project)
                case "rename":
                    _ = try await repository.rename("dangling.md", in: project, to: "renamed.md")
                default:
                    _ = try await repository.move("dangling.md", in: project, to: "real-parent")
                }
                XCTFail("Expected dangling symlink \(operation) to be rejected")
            } catch let error as FileSystemRepositoryError {
                XCTAssertEqual(error, .pathEscapesProject)
            }
        }
        XCTAssertEqual(
            try dangling.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink,
            true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testSymlinksCannotReadOrDeleteOutsideProject() async throws {
        let directory = try TemporaryDirectory()
        let repository = LocalProjectRepository()
        let workspace = try await repository.createWorkspace(at: directory.url.appendingPathComponent("Workspace"))
        let project = try await repository.createProject(named: "Notes", in: workspace)
        let outside = directory.url.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let protectedFile = outside.appendingPathComponent("private.md")
        try Data("private contents".utf8).write(to: protectedFile)
        try FileManager.default.createSymbolicLink(
            at: project.rootURL.appendingPathComponent("escape"), withDestinationURL: outside
        )

        do {
            _ = try await repository.children(of: "escape", in: project)
            XCTFail("Expected symlink escape to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        do {
            try await repository.delete("escape/private.md", in: project)
            XCTFail("Expected deletion through symlink escape to be rejected")
        } catch let error as FileSystemRepositoryError {
            XCTAssertEqual(error, .pathEscapesProject)
        }
        XCTAssertEqual(try String(contentsOf: protectedFile, encoding: .utf8), "private contents")
    }

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
