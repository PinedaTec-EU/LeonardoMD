import Foundation
import SwiftUI
import LeonardoCore
import LeonardoRender

/// The signing-copy reader is deliberately presentation-only. It renders the
/// immutable source carried by the exchange and reports only the exact DOM
/// occurrences that the renderer exposed. It has no document-store or form
/// editing capability.
struct MobileGuidedSigningDocumentReader: View {
    let document: LeonardoDocument
    let resources: [LeonardoSigningResource]
    let session: LeonardoGuidedSigningSession
    let trustedCredentials: [LeonardoSigningCredential]
    let trustAccepted: Bool
    let focusTarget: LeonardoSigningLocationTarget?
    let onFocusConsumed: () -> Void
    @Binding private var availableTargetKeys: Set<String>
    @StateObject private var controller = MarkdownPreviewController()

    private let virtualRoot = URL(fileURLWithPath: "/LittleLeonardoSigning", isDirectory: true)

    init(
        document: LeonardoDocument,
        resources: [LeonardoSigningResource],
        session: LeonardoGuidedSigningSession,
        trustedCredentials: [LeonardoSigningCredential],
        trustAccepted: Bool,
        focusTarget: LeonardoSigningLocationTarget?,
        availableTargetKeys: Binding<Set<String>>,
        onFocusConsumed: @escaping () -> Void
    ) {
        self.document = document
        self.resources = resources
        self.session = session
        self.trustedCredentials = trustedCredentials
        self.trustAccepted = trustAccepted
        self.focusTarget = focusTarget
        self._availableTargetKeys = availableTargetKeys
        self.onFocusConsumed = onFocusConsumed
    }

    private var source: String? {
        try? LeonardoFormatParser.serialize(document)
    }

    private var memoryAssets: MarkdownMemoryAssets {
        MarkdownMemoryAssets(files: Dictionary(
            resources.map { ($0.reference, $0.bytes) },
            uniquingKeysWith: { first, _ in first }
        ))
    }

    private var guidedSigningFieldIDs: [String] {
        document.metadata.fields.compactMap { fieldID, field in
            field.type == .rubric && field.signerPosition != nil ? fieldID : nil
        }.sorted()
    }

    private var verifiedRubricOverlays: [String: LeonardoRubric] {
        guard trustAccepted,
              let trustStore = try? LeonardoSigningTrustRegistry(credentials: trustedCredentials) else {
            return [:]
        }
        let verification = session.signatureVerification(
            document: document,
            resources: resources,
            trustStore: trustStore
        )
        var overlays: [String: LeonardoRubric] = [:]
        for (positionID, progress) in session.positions
            where progress.state == .signed && progress.signature != nil
                && verification[positionID] == .valid {
            for location in progress.locations {
                overlays[MobileGuidedSigningTargetKey.make(fieldID: location.fieldID, occurrence: location.occurrence)] = location.rubric
            }
        }
        return overlays
    }

    private var previewConfiguration: MarkdownPreviewConfiguration {
        var configuration = MarkdownPreviewConfiguration(
            allowsMermaid: true,
            allowsMath: true,
            externalLinkPolicy: .blocked,
            appearance: .leonardoClassic,
            localAssetRoot: virtualRoot,
            memoryAssets: memoryAssets,
            allowsRemoteImages: false
        )
        configuration.allowsLeonardoFormat = source != nil
        configuration.guidedSigningFieldIDs = guidedSigningFieldIDs
        configuration.guidedSigningRubricOverlays = verifiedRubricOverlays
        return configuration
    }

    private var renderedTargets: [LeonardoSigningLocationTarget] {
        session.declaration.positions.flatMap { position in
            (try? session.targets(for: position.id, document: document)) ?? []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                "Documento completo · solo lectura / Full document · read-only",
                systemImage: "doc.text.magnifyingglass"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MobileClassic.heading)
            Text("Lee la copia completa y usa «Ver ubicación» para saltar a la aparición exacta. / Read the complete copy and use “View location” to jump to the exact occurrence.")
                .font(.caption)
                .foregroundStyle(MobileClassic.secondary)

            if let source {
                MarkdownPreview(
                    content: source,
                    baseURL: virtualRoot.appendingPathComponent("signing-copy.mdlf"),
                    configuration: previewConfiguration,
                    controller: controller
                )
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("mobile-signing-document-preview")
            } else {
                Label(
                    "No se puede renderizar la copia / The signing copy cannot be rendered",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .onAppear { refreshAvailableTargets() }
        .onChange(of: controller.isReady) { _, ready in
            if ready { refreshAvailableTargets(); focusPendingTarget() }
        }
        .onChange(of: renderedTargetKeys) { _, _ in refreshAvailableTargets() }
        .onChange(of: focusTarget) { _, _ in focusPendingTarget() }
        .onDisappear { availableTargetKeys = [] }
    }

    private var renderedTargetKeys: [String] {
        renderedTargets.map { MobileGuidedSigningTargetKey.make(fieldID: $0.fieldID, occurrence: $0.occurrence) }
    }

    private func refreshAvailableTargets() {
        guard controller.isReady else {
            availableTargetKeys = []
            return
        }
        let targets = renderedTargets
        let expectedKeys = Set(targets.map {
            MobileGuidedSigningTargetKey.make(fieldID: $0.fieldID, occurrence: $0.occurrence)
        })
        Task { @MainActor in
            var available = Set<String>()
            for target in targets {
                if await controller.hasFieldTarget(target.fieldID, occurrence: target.occurrence) {
                    available.insert(MobileGuidedSigningTargetKey.make(fieldID: target.fieldID, occurrence: target.occurrence))
                }
            }
            guard Set(renderedTargetKeys) == expectedKeys else { return }
            availableTargetKeys = available
        }
    }

    private func focusPendingTarget() {
        guard let focusTarget, controller.isReady else { return }
        Task { @MainActor in
            let key = MobileGuidedSigningTargetKey.make(fieldID: focusTarget.fieldID, occurrence: focusTarget.occurrence)
            guard await controller.hasFieldTarget(focusTarget.fieldID, occurrence: focusTarget.occurrence) else {
                availableTargetKeys.remove(key)
                onFocusConsumed()
                return
            }
            controller.scroll(toField: focusTarget.fieldID, occurrence: focusTarget.occurrence)
            availableTargetKeys.insert(key)
            onFocusConsumed()
        }
    }
}

enum MobileGuidedSigningTargetKey {
    static func make(fieldID: String, occurrence: Int) -> String {
        "\(fieldID)#\(occurrence)"
    }
}
