import Foundation

/// The signed bundle is a template. Saving the guide only changes this user's copy.
enum BundledUserGuide {
    static func resourceURL(language: AppLanguage) throws -> URL {
        guard let url = Bundle.module.url(forResource: "Guide-v3-" + language.rawValue, withExtension: "mdlz") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }

    static func workingCopy(language: AppLanguage, supportDirectory: URL) throws -> URL {
        let source = try resourceURL(language: language)
        let directory = supportDirectory.appendingPathComponent("User Guides/v3/" + language.rawValue, isDirectory: true)
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
    func openUserGuide() async {
        guard acceptsExternalDrops else { return }
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)
                .appendingPathComponent("LeonardoMD", isDirectory: true)
            let copy = try BundledUserGuide.workingCopy(language: LanguageSettings.shared.language,
                                                      supportDirectory: support)
            await openExternalDocuments([copy], packagePreference: .package)
        } catch {
            activeSession.report(error)
        }
    }
}
