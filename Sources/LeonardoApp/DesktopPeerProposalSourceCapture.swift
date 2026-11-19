import Foundation
import LeonardoSync

enum DesktopPeerProposalSourceCaptureError: Error {
    case ambiguousBuffers
}

/// Captures the exact file view negotiated for one incoming peer proposal.
enum DesktopPeerProposalSourceCapture {
    static func source(root: URL, view: DesktopPeerUploadView,
                       buffers: [OpenDocumentBuffer]) async throws -> CorpusSnapshot {
        try await ProjectCorpusReader().snapshot(root: root, selection: view.selection,
            buffers: selectedBuffers(buffers, view: view), excludingExtensions: view.excludedExtensions)
    }

    static func current(root: URL, view: DesktopPeerUploadView,
                        buffers: [OpenDocumentBuffer]) async throws -> (source: CorpusSnapshot, disk: CorpusSnapshot) {
        let selected = selectedBuffers(buffers, view: view)
        for group in Dictionary(grouping: selected, by: \.path).values where Set(group.map(\.text)).count > 1 {
            throw DesktopPeerProposalSourceCaptureError.ambiguousBuffers
        }
        let reader = ProjectCorpusReader()
        let disk = try await reader.snapshot(root: root, selection: view.selection,
            excludingExtensions: view.excludedExtensions)
        let source = try await reader.snapshot(root: root, selection: view.selection,
            buffers: selected, excludingExtensions: view.excludedExtensions)
        return (source, disk)
    }

    private static func selectedBuffers(_ buffers: [OpenDocumentBuffer],
                                        view: DesktopPeerUploadView) -> [OpenDocumentBuffer] {
        buffers.filter { buffer in
            view.selection.contains(buffer.path) &&
                !view.excludedExtensions.contains((buffer.path as NSString).pathExtension.lowercased())
        }
    }
}
