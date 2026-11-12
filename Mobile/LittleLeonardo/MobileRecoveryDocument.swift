import SwiftUI
import UniformTypeIdentifiers
import LeonardoSync

/// A credential-free copy of the original corpus state, exported without changing the cache.
struct MobileRecoveryDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    private let project: OfflineProject

    init(project: OfflineProject) { self.project = project }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw SyncError.invalidSnapshot }
        project = try JSONDecoder().decode(CorpusRecoveryArchive.self, from: data).project
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(regularFileWithContents: CorpusRecoveryArchive(project: project).encoded())
    }
}
