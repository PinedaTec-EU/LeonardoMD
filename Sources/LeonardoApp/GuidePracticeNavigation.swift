import Foundation

struct GuidePracticeRequest {
    let destination: URL
    let document: URL?
    let source: String
}

enum GuidePracticeResult: Equatable {
    case opened, rejected, notApplicable
}

/// A fixed bundled resource, never a document-selected command or filesystem path.
enum BundledGuidePractice {
    static func link(language: AppLanguage) -> URL {
        URL(string: "https://github.com/PinedaTec-EU/LeonardoMD/blob/main/doc/guide/\(language.rawValue)/practice.mdlr")!
    }

    static func recognizes(_ url: URL) -> Bool {
        AppLanguage.allCases.contains { link(language: $0).absoluteString == url.absoluteString }
    }

    static func workingCopy(language: AppLanguage, supportDirectory: URL) throws -> URL {
        guard let source = Bundle.module.url(forResource: "Practice-v1-" + language.rawValue, withExtension: "mdlr") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = supportDirectory.appendingPathComponent("Practice Forms/v1/" + language.rawValue, isDirectory: true)
        return try BundledUserGuide.copyIfAbsent(source, to: directory)
    }
}

extension DocumentTabs {
    func configureGuidePractice(for session: AppSession, guide: URL, language: AppLanguage, supportDirectory: URL) {
        session.openGuidePractice = { [weak self, weak session] request in
            guard let self, let session, self.acceptsExternalDrops,
                  !session.stopped, !session.isClosing else { return .rejected }
            // The preview must still belong to this live document and buffer.
            guard session.documentURL == request.document, session.content == request.source else { return .rejected }
            guard session.displayDocumentURL == guide else { return .notApplicable }
            guard self.activeSession === session, !session.busy, !session.gitBusy,
                  !session.isSyncSuspended, !session.isCapturingPreview,
                  request.destination.absoluteString == BundledGuidePractice.link(language: language).absoluteString else { return .rejected }
            do {
                let copy = try BundledGuidePractice.workingCopy(language: language, supportDirectory: supportDirectory)
                await self.openExternalDocuments([copy])
                guard self.acceptsExternalDrops,
                      let practice = self.tabs.first(where: { $0.session.displayDocumentURL == copy })?.session,
                      !practice.stopped, !practice.isClosing, practice.leonardoDocument?.isForm == true else { return .rejected }
                await practice.setDocumentMode(.fill)
                guard practice.displayDocumentURL == copy, practice.canFillLeonardoForm else { return .rejected }
                return .opened
            } catch {
                session.report(error)
                return .rejected
            }
        }
    }
}

extension AppSession {
    func followPreviewLink(_ request: GuidePracticeRequest) async {
        guard !stopped, documentURL == request.document, content == request.source else { return }
        if BundledGuidePractice.recognizes(request.destination) {
            switch await openGuidePractice(request) {
            case .opened, .rejected: return
            case .notApplicable: break
            }
        }
        await followLink(request.destination)
    }
}
