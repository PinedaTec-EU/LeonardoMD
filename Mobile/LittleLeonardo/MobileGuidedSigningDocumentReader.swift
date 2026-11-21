import Foundation
import SwiftUI
import UIKit
import LeonardoCore
import LeonardoRender

/// The signing-copy reader is deliberately presentation-only. It presents the
/// immutable source carried by the exchange, with native exact occurrences
/// available before an optional WebKit render proves itself. It has no
/// document-store or form editing capability.
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
    // The native source is available from the first frame. WebKit may replace
    // it only after it has exposed every exact target occurrence.
    @State private var showingNativeFallback = true

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
                ZStack(alignment: .topLeading) {
                    MarkdownPreview(
                        content: source,
                        // MarkdownPreview receives the containing directory, as
                        // does MobileDocumentView. Passing the synthetic file URL
                        // makes the WebKit resource base one level too deep and
                        // can leave a signing copy blank while ordinary readers
                        // still render normally.
                        baseURL: virtualRoot,
                        configuration: previewConfiguration,
                        controller: controller
                    )
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(showingNativeFallback ? 0 : 1)
                    .accessibilityIdentifier("mobile-signing-document-preview")

                    if showingNativeFallback {
                        MobileGuidedSigningSourceFallback(
                            document: document,
                            resources: resources,
                            session: session,
                            rubricOverlays: verifiedRubricOverlays,
                            focusTarget: focusTarget,
                            availableTargetKeys: $availableTargetKeys,
                            onFocusConsumed: onFocusConsumed
                        )
                        .frame(maxHeight: 420)
                        .background(MobileClassic.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("mobile-signing-native-fallback")
                    }
                }
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
            if ready {
                let targets = renderedTargets
                let expectedKeys = Set(targets.map {
                    MobileGuidedSigningTargetKey.make(fieldID: $0.fieldID, occurrence: $0.occurrence)
                })
                Task { @MainActor in
                    let available = await availableTargetKeys(for: targets)
                    guard Set(renderedTargetKeys) == expectedKeys else { return }
                    availableTargetKeys = available
                    // A WebKit host can report ready after a document that is
                    // visibly empty. Keep the native fallback selected until
                    // every exact occurrence is actually present.
                    if expectedKeys.isEmpty || expectedKeys.isSubset(of: available) {
                        showingNativeFallback = false
                        focusPendingTarget()
                    }
                }
            }
        }
        .onChange(of: renderedTargetKeys) { _, _ in refreshAvailableTargets() }
        .onChange(of: focusTarget) { _, _ in focusPendingTarget() }
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
            let available = await availableTargetKeys(for: targets)
            guard Set(renderedTargetKeys) == expectedKeys else { return }
            availableTargetKeys = available
        }
    }

    private func availableTargetKeys(for targets: [LeonardoSigningLocationTarget]) async -> Set<String> {
        guard controller.isReady else { return [] }
        var available = Set<String>()
        for target in targets {
            if await controller.hasFieldTarget(target.fieldID, occurrence: target.occurrence) {
                available.insert(MobileGuidedSigningTargetKey.make(
                    fieldID: target.fieldID, occurrence: target.occurrence
                ))
            }
        }
        return available
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

enum MobileGuidedSigningNativeContent {
    static func readableBody(from document: LeonardoDocument) -> String {
        LeonardoMarkdownExport.markdown(from: document)
    }

    static func referencedResourceReferences(from document: LeonardoDocument) -> Set<String> {
        guard let source = try? LeonardoFormatParser.serialize(document) else { return [] }
        return Set(LeonardoLocalImagePolicy.localReferences(in: source))
    }
}

private extension LeonardoSigningLocationTarget {
    var mobileStableID: String {
        "\(positionID)#\(fieldID)#\(occurrence)"
    }
}

/// A deliberately plain, read-only path that is available while WebKit loads
/// (or when it never reports ready). It keeps the exchange usable without
/// pretending that a DOM location exists: targets are exposed only at the
/// exact source occurrences represented by the native session, and every
/// confirmation still goes through the existing Core validation.
private struct MobileGuidedSigningSourceFallback: View {
    let document: LeonardoDocument
    let resources: [LeonardoSigningResource]
    let session: LeonardoGuidedSigningSession
    let rubricOverlays: [String: LeonardoRubric]
    let focusTarget: LeonardoSigningLocationTarget?
    @Binding var availableTargetKeys: Set<String>
    let onFocusConsumed: () -> Void

    private var targets: [LeonardoSigningLocationTarget] {
        session.declaration.positions.flatMap { position in
            (try? session.targets(for: position.id, document: document)) ?? []
        }
    }

    /// The native reader must not leave ordinary form values as raw
    /// `{{field:...}}` tokens. LeonardoMarkdownExport also removes local image
    /// syntax, which is why the sealed resources are listed/rendered below.
    private var readableBody: String {
        MobileGuidedSigningNativeContent.readableBody(from: document)
    }

    private var referencedResourceReferences: Set<String> {
        MobileGuidedSigningNativeContent.referencedResourceReferences(from: document)
    }

    private var referencedResources: [LeonardoSigningResource] {
        let references = referencedResourceReferences
        return resources
            .filter { references.contains($0.reference) }
            .sorted { $0.reference < $1.reference }
    }

    private var missingResourceReferences: [String] {
        let available = Set(resources.map(\.reference))
        return referencedResourceReferences.subtracting(available).sorted()
    }

    private var unrenderedResourceReferences: [String] {
        referencedResources.compactMap { resource in
            UIImage(data: resource.bytes) == nil ? resource.reference : nil
        }
    }

    private var nativeContentComplete: Bool {
        missingResourceReferences.isEmpty && unrenderedResourceReferences.isEmpty
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        "Lectura nativa de respaldo · Native read-only fallback",
                        systemImage: "text.book.closed"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileClassic.secondary)
                    Text(document.metadata.document.title ?? "Signing copy")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(MobileClassic.heading)
                    Text(readableBody)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(MobileClassic.inset)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("mobile-signing-native-source")

                    if !referencedResources.isEmpty || !missingResourceReferences.isEmpty {
                        Divider()
                        Text("Recursos sellados / Sealed resources")
                            .font(.headline)
                            .foregroundStyle(MobileClassic.heading)
                        ForEach(referencedResources, id: \.reference) { resource in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(resource.reference)
                                    .font(.subheadline.weight(.semibold))
                                if let image = UIImage(data: resource.bytes) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 180)
                                        .frame(maxWidth: .infinity)
                                        .accessibilityLabel(resource.reference)
                                } else {
                                    Label(
                                        "Este recurso no se puede mostrar aquí; la confirmación queda bloqueada. / This resource cannot be shown here; confirmation is blocked.",
                                        systemImage: "exclamationmark.triangle"
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MobileClassic.inset)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("mobile-signing-native-resource-\(resource.reference)")
                        }
                        ForEach(missingResourceReferences, id: \.self) { reference in
                            Label(
                                "Falta el recurso sellado \(reference); la confirmación queda bloqueada. / Sealed resource \(reference) is missing; confirmation is blocked.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    }

                    if !nativeContentComplete {
                        Label(
                            "La lectura nativa no representa todo el material sellado; no se puede confirmar hasta mostrarlo. / The native reader does not represent all sealed material; confirmation is blocked until it is shown.",
                            systemImage: "lock.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("mobile-signing-native-content-incomplete")
                    }

                    if !targets.isEmpty {
                        Divider()
                        Text("Apariciones exactas / Exact occurrences")
                            .font(.headline)
                            .foregroundStyle(MobileClassic.heading)
                        ForEach(targets, id: \.mobileStableID) { target in
                            let key = MobileGuidedSigningTargetKey.make(
                                fieldID: target.fieldID, occurrence: target.occurrence
                            )
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(target.fieldID) · \(target.occurrence + 1)")
                                    .font(.subheadline.weight(.semibold))
                                Text(context(for: target))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(MobileClassic.secondary)
                                    .textSelection(.enabled)
                                if let rubric = rubricOverlays[key] {
                                    MobileRubricPreview(rubric: rubric)
                                        .frame(maxHeight: 120)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MobileClassic.inset)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .id(key)
                            .accessibilityIdentifier("mobile-signing-native-target-\(target.fieldID)-\(target.occurrence)")
                        }
                    } else {
                        Label(
                            "No hay apariciones exactas disponibles; la confirmación permanece bloqueada. / No exact occurrences are available; confirmation remains blocked.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }
                .padding(12)
            }
            .onAppear {
                if nativeContentComplete {
                    availableTargetKeys.formUnion(targets.map {
                        MobileGuidedSigningTargetKey.make(fieldID: $0.fieldID, occurrence: $0.occurrence)
                    })
                }
                focus(focusTarget, using: proxy)
            }
            .onChange(of: focusTarget) { _, target in
                focus(target, using: proxy)
            }
        }
    }

    private func focus(_ target: LeonardoSigningLocationTarget?, using proxy: ScrollViewProxy) {
        guard let target else { return }
        let key = MobileGuidedSigningTargetKey.make(fieldID: target.fieldID, occurrence: target.occurrence)
        guard targets.contains(where: {
            $0.fieldID == target.fieldID && $0.occurrence == target.occurrence
        }) else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(key, anchor: .center)
            onFocusConsumed()
        }
    }

    private func context(for target: LeonardoSigningLocationTarget) -> String {
        guard target.sourceOffset >= 0,
              let start = document.body.index(
                document.body.startIndex,
                offsetBy: target.sourceOffset,
                limitedBy: document.body.endIndex
              ) else {
            return document.body.prefix(160).description
        }
        let lower = document.body.index(start, offsetBy: -120, limitedBy: document.body.startIndex)
            ?? document.body.startIndex
        let upper = document.body.index(start, offsetBy: 180, limitedBy: document.body.endIndex)
            ?? document.body.endIndex
        return String(document.body[lower..<upper]).replacingOccurrences(of: "\n", with: " ↵ ")
    }
}
