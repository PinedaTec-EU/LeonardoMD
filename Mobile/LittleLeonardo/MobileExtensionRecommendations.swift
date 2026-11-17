import Combine
import Foundation
import LeonardoCore

struct MobileExtensionRecommendation: Identifiable {
    let id = UUID()
    let document: MobileDocumentIdentity
    let source: String
    let extensions: [BuiltInExtension]
}

struct MobileExtensionRecommendationChoice {
    var enabledExtensions: Set<BuiltInExtension> = []
    var suppressWarnings = false
}

@MainActor
final class MobileExtensionRecommendations: ObservableObject {
    private struct Offer: Hashable {
        let document: MobileDocumentIdentity
        let sourceHash: Int
        let item: BuiltInExtension
    }

    private struct Detection {
        let document: MobileDocumentIdentity
        let source: String
        let identifiers: [String]
    }

    @Published private(set) var prompt: MobileExtensionRecommendation?
    private var offered: Set<Offer> = []
    private var lastDetection: Detection?
    private var extensionWarningResetRevision = 0
    private(set) var activeDocument: MobileDocumentIdentity?

    func activate(document: MobileDocumentIdentity, preferences: MobileMarkdownPreferences) {
        activeDocument = document
        if prompt?.document != document { prompt = nil }
        synchronizeWarningReset(preferences: preferences)
        if let lastDetection, lastDetection.document == document {
            offer(lastDetection, preferences: preferences)
        }
    }

    func deactivate(document: MobileDocumentIdentity) {
        guard activeDocument == document else { return }
        activeDocument = nil
        prompt = nil
    }

    func documentContentWillReload(_ document: MobileDocumentIdentity) {
        guard activeDocument == document else { return }
        prompt = nil
        if lastDetection?.document == document { lastDetection = nil }
    }

    func dismissPrompt() {
        prompt = nil
    }

    func warningPreferencesDidReset(preferences: MobileMarkdownPreferences) {
        synchronizeWarningReset(preferences: preferences)
        guard let lastDetection, lastDetection.document == activeDocument else { return }
        offer(lastDetection, preferences: preferences)
    }

    func inspect(document: MobileDocumentIdentity, source: String, detectedIDs: [String],
                 preferences: MobileMarkdownPreferences) {
        guard activeDocument == document else { return }
        synchronizeWarningReset(preferences: preferences)
        let detection = Detection(document: document, source: source, identifiers: detectedIDs)
        lastDetection = detection
        offer(detection, preferences: preferences)
    }

    func respond(to request: MobileExtensionRecommendation, choice: MobileExtensionRecommendationChoice,
                 enableSelected: Bool, preferences: MobileMarkdownPreferences) {
        guard prompt?.id == request.id else { return }
        prompt = nil
        guard activeDocument == request.document,
              lastDetection?.document == request.document,
              lastDetection?.source == request.source else { return }

        preferences.setSuppressesExtensionWarnings(choice.suppressWarnings)
        guard enableSelected else { return }

        let selected = choice.enabledExtensions.intersection(request.extensions)
        guard !selected.isEmpty else { return }
        var features = preferences.features
        for item in selected {
            features[keyPath: item.flag] = true
        }
        preferences.setFeatures(features)
    }

    private func synchronizeWarningReset(preferences: MobileMarkdownPreferences) {
        guard extensionWarningResetRevision != preferences.extensionWarningResetRevision else { return }
        extensionWarningResetRevision = preferences.extensionWarningResetRevision
        offered = []
        prompt = nil
    }

    private func offer(_ detection: Detection, preferences: MobileMarkdownPreferences) {
        guard activeDocument == detection.document else { return }
        if let prompt, prompt.document != detection.document || prompt.source != detection.source {
            self.prompt = nil
        }
        guard prompt == nil, !preferences.suppressesExtensionWarnings else { return }

        let detected = Set(detection.identifiers.compactMap(BuiltInExtension.init(rawValue:)))
        let missing = BuiltInExtension.allCases.filter { item in
            detected.contains(item)
                && !preferences.features[keyPath: item.flag]
                && !offered.contains(Offer(document: detection.document,
                                           sourceHash: detection.source.hashValue, item: item))
        }
        guard !missing.isEmpty else { return }

        offered.formUnion(missing.map {
            Offer(document: detection.document, sourceHash: detection.source.hashValue, item: $0)
        })
        prompt = MobileExtensionRecommendation(document: detection.document, source: detection.source,
                                                extensions: missing)
    }
}
