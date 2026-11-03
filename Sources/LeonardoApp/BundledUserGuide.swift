import Foundation

/// The signed bundle is a template. Saving the guide only changes this user's copy.
enum BundledUserGuide {
    static func resourceURL(language: AppLanguage) throws -> URL {
        guard let url = Bundle.module.url(forResource: "Guide-v6-" + language.rawValue, withExtension: "mdlz") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    static func workingCopy(language: AppLanguage, supportDirectory: URL) throws -> URL {
        let source = try resourceURL(language: language)
        let directory = supportDirectory.appendingPathComponent("User Guides/v6/" + language.rawValue, isDirectory: true)
        return try copyIfAbsent(source, to: directory)
    }

    static func copyIfAbsent(_ source: URL, to directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        // Never overwrite a reader's saved practice answers on reopening.
        if !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        return destination
    }
}

extension DocumentTabs {
    func openUserGuide(language: AppLanguage? = nil, supportDirectory: URL? = nil) async {
        guard acceptsExternalDrops else { return }
        do {
            let language = language ?? LanguageSettings.shared.language
            let support = try supportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
                .appendingPathComponent("LeonardoMD", isDirectory: true)
            let copy = try BundledUserGuide.workingCopy(language: language,
                                                      supportDirectory: support)
            let alreadyOpen = tabs.contains { $0.session.displayDocumentURL == copy }
            await openExternalDocuments([copy], packagePreference: .package)
            guard acceptsExternalDrops,
                  let session = tabs.first(where: { $0.session.displayDocumentURL == copy })?.session else { return }
            if !alreadyOpen { session.mode = .preview }
            configureGuidePractice(for: session, guide: copy, language: language, supportDirectory: support)
        } catch {
            activeSession.report(error)
        }
    }
}
