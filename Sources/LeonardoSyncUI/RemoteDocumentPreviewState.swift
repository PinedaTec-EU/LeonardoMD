import Foundation
import LeonardoSync

struct RemoteDocumentPreviewRequest: Hashable {
    let projectID: UUID
    let path: String
    let catalogue: RemoteProjectCatalogue?
}

/// A presentation belongs to one catalogue load, including its dependent images.
struct RemoteDocumentPreviewState {
    private var request: RemoteDocumentPreviewRequest?
    private var generation = UUID()
    private var file: CorpusFile?
    private var images: [String: Data] = [:]
    private var failure: String?

    mutating func begin(_ request: RemoteDocumentPreviewRequest) -> UUID {
        generation = UUID()
        self.request = request
        file = nil
        images = [:]
        failure = nil
        return generation
    }

    mutating func receive(_ file: CorpusFile, ticket: UUID) {
        guard ticket == generation else { return }
        self.file = file
    }

    mutating func receiveImage(_ data: Data, path: String, ticket: UUID) {
        guard ticket == generation else { return }
        images[path] = data
    }

    mutating func fail(_ message: String, ticket: UUID) {
        guard ticket == generation else { return }
        failure = message
    }

    func content(for current: RemoteDocumentPreviewRequest) -> CorpusFile? {
        current.catalogue != nil && request == current ? file : nil
    }

    func assets(for current: RemoteDocumentPreviewRequest) -> [String: Data] {
        current.catalogue != nil && request == current ? images : [:]
    }

    func error(for current: RemoteDocumentPreviewRequest) -> String? {
        current.catalogue != nil && request == current ? failure : nil
    }
}
