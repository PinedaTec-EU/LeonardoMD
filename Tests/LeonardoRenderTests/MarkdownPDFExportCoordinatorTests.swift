import Foundation
import Testing
@testable import LeonardoRender

@MainActor
struct MarkdownPDFExportCoordinatorTests {
    @Test func queuedCancellationCompletesBeforeOwnerRelease() async throws {
        let exports = MarkdownPDFExportCoordinator()
        defer { exports.invalidate() }
        let owner = try await exports.acquire()
        var returned = false
        let queued = Task {
            defer { returned = true }
            return try await exports.acquire()
        }
        await Task.yield()
        queued.cancel()
        try await eventually { returned }
        #expect(exports.owns(owner))
        await #expect(throws: CancellationError.self) { try await queued.value }
        exports.release(owner)
        let next = try await exports.acquire()
        exports.release(next)
    }

    @Test func invalidationFailsPendingCaptureAndQueueAndIgnoresOldCompletion() async throws {
        let exports = MarkdownPDFExportCoordinator()
        defer { exports.invalidate() }
        let owner = try await exports.acquire()
        var oldCompletion: MarkdownPDFExportCoordinator.PDFCompletion?
        let active = Task {
            try await exports.createPDF(ticket: owner) { oldCompletion = $0 }
        }
        try await eventually { oldCompletion != nil }
        var queuedReturned = false
        let queued = Task {
            defer { queuedReturned = true }
            return try await exports.acquire()
        }
        await Task.yield()
        exports.invalidate(with: MarkdownRenderError.renderTimedOut)
        try await eventually { queuedReturned }
        await #expect(throws: MarkdownRenderError.self) { try await active.value }
        await #expect(throws: MarkdownRenderError.self) { try await queued.value }

        let replacement = try await exports.acquire()
        var newCompletion: MarkdownPDFExportCoordinator.PDFCompletion?
        var replacementReturned = false
        let capture = Task {
            defer { replacementReturned = true }
            return try await exports.createPDF(ticket: replacement) { newCompletion = $0 }
        }
        try await eventually { newCompletion != nil }
        oldCompletion?(.success(Data("obsolete".utf8)))
        exports.release(owner)
        #expect(exports.owns(replacement))
        #expect(!replacementReturned)
        let bytes = Data("current PDF".utf8)
        newCompletion?(.success(bytes))
        let result = try await capture.value
        #expect(result == bytes)
        exports.release(replacement)
    }

    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}
