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
    @State private var memoryAssets: MarkdownMemoryAssets
    @State private var isReaderVisible = false
    // The native source is available from the first frame. WebKit may replace
    // it only after it has exposed every exact target occurrence.
    @State private var showingNativeFallback = true

    private var spanish: Bool {
        MobileErrorNotice.isSpanishLanguage(Locale.preferredLanguages.first)
    }

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
        self._memoryAssets = State(initialValue: Self.makeMemoryAssets(resources))
    }

    private var source: String? {
        try? LeonardoFormatParser.serialize(document)
    }

    private static func makeMemoryAssets(_ resources: [LeonardoSigningResource]) -> MarkdownMemoryAssets {
        let byPath = Dictionary(grouping: resources) {
            URLComponents(string: $0.reference)?.path ?? $0.reference
        }
        return MarkdownMemoryAssets(files: byPath.compactMapValues { aliases in
            guard let bytes = aliases.first?.bytes,
                  aliases.allSatisfy({ $0.bytes == bytes }) else { return nil }
            return bytes
        })
    }

    private var guidedSigningFieldIDs: [String] {
        document.metadata.fields.compactMap { fieldID, field in
            field.type == .rubric && field.signerPosition != nil ? fieldID : nil
        }.sorted()
    }

    private func webPreviewHasReferencedImages() async -> Bool {
        let references = MobileGuidedSigningNativeContent.referencedResourceReferences(from: document)
        guard references.isSubset(of: Set(resources.map(\.reference))),
              let embedded = try? LeonardoLocalImagePolicy.hasEmbeddedSigningImages(in: document) else {
            return false
        }
        guard !references.isEmpty || embedded else { return true }
        return await controller.hasRenderedLocalImages(
            references.map { URLComponents(string: $0)?.path ?? $0 },
            includesEmbeddedImages: embedded
        )
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
                spanish ? "Solo lectura" : "Read-only",
                systemImage: "lock"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MobileClassic.heading)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .opacity(showingNativeFallback ? 0 : 1)
                    .accessibilityIdentifier("mobile-signing-document-preview")

                    if showingNativeFallback {
                        MobileGuidedSigningSourceFallback(
                            document: document,
                            spanish: spanish,
                            resources: resources,
                            session: session,
                            rubricOverlays: verifiedRubricOverlays,
                            focusTarget: focusTarget,
                            availableTargetKeys: $availableTargetKeys,
                            onFocusConsumed: onFocusConsumed
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("mobile-signing-native-fallback")
                    }
                }
            } else {
                Label(
                    spanish ? "No se puede renderizar la copia" : "The signing copy cannot be rendered",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MobileClassic.paper)
        .onAppear {
            isReaderVisible = true
            refreshAvailableTargets()
        }
        .onDisappear { isReaderVisible = false }
        .onChange(of: controller.isReady) { _, ready in
            guard ready else {
                // Native content owns the shared availability while WebKit is
                // absent or being replaced. Clear first so stale DOM results
                // cannot keep a confirmation button enabled.
                if !showingNativeFallback {
                    availableTargetKeys = []
                    showingNativeFallback = true
                }
                return
            }
            let targets = renderedTargets
            let expectedKeys = targetKeys(for: targets)
            let expectedAssets = memoryAssets
            Task { @MainActor in
                let available = await availableTargetKeys(for: targets)
                guard isReaderVisible, showingNativeFallback, memoryAssets === expectedAssets,
                      Set(renderedTargetKeys) == expectedKeys,
                      controller.isReady else { return }
                // A ready host can still be visibly empty. Keep native
                // ownership until every exact occurrence is present.
                guard expectedKeys.isEmpty || expectedKeys.isSubset(of: available) else { return }
                showingNativeFallback = false
                availableTargetKeys = available
                focusPendingTarget()
            }
        }
        .onChange(of: renderedTargetKeys) { _, _ in refreshAvailableTargets() }
        .onChange(of: resources) { _, resources in
            availableTargetKeys = []
            showingNativeFallback = true
            memoryAssets = Self.makeMemoryAssets(resources)
        }
        .onChange(of: focusTarget) { _, _ in focusPendingTarget() }
    }

    private var renderedTargetKeys: [String] {
        renderedTargets.map { MobileGuidedSigningTargetKey.make(fieldID: $0.fieldID, occurrence: $0.occurrence) }
    }

    private func targetKeys(for targets: [LeonardoSigningLocationTarget]) -> Set<String> {
        Set(targets.map {
            MobileGuidedSigningTargetKey.make(fieldID: $0.fieldID, occurrence: $0.occurrence)
        })
    }

    private func refreshAvailableTargets() {
        // The native reader publishes its own exact anchors. WebKit may only
        // publish after it has been promoted by the readiness check above.
        guard !showingNativeFallback else { return }
        guard controller.isReady else {
            availableTargetKeys = []
            showingNativeFallback = true
            return
        }
        let targets = renderedTargets
        let expectedKeys = targetKeys(for: targets)
        let expectedAssets = memoryAssets
        Task { @MainActor in
            let available = await availableTargetKeys(for: targets)
            guard isReaderVisible, !showingNativeFallback, memoryAssets === expectedAssets,
                  controller.isReady,
                  Set(renderedTargetKeys) == expectedKeys else { return }
            guard expectedKeys.isEmpty || expectedKeys.isSubset(of: available) else {
                availableTargetKeys = []
                showingNativeFallback = true
                return
            }
            availableTargetKeys = available
        }
    }

    private func availableTargetKeys(for targets: [LeonardoSigningLocationTarget]) async -> Set<String> {
        guard controller.isReady, await webPreviewHasReferencedImages() else { return [] }
        let expectedCounts = Dictionary(grouping: renderedTargets, by: \.fieldID).mapValues(\.count)
        var available = Set<String>()
        for target in targets {
            if let count = expectedCounts[target.fieldID],
               await controller.hasFieldTarget(target.fieldID, occurrence: target.occurrence, expectedCount: count) {
                available.insert(MobileGuidedSigningTargetKey.make(
                    fieldID: target.fieldID, occurrence: target.occurrence
                ))
            }
        }
        return available
    }

    private func focusPendingTarget() {
        guard !showingNativeFallback,
              let focusTarget, controller.isReady else { return }
        let expectedAssets = memoryAssets
        Task { @MainActor in
            let key = MobileGuidedSigningTargetKey.make(fieldID: focusTarget.fieldID, occurrence: focusTarget.occurrence)
            let available = await availableTargetKeys(for: [focusTarget]).contains(key)
            guard isReaderVisible, !showingNativeFallback,
                  memoryAssets === expectedAssets, controller.isReady else { return }
            guard available else {
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
        var result = LeonardoMarkdownExport.markdown(from: document)
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
        guard let expression = try? NSRegularExpression(
            pattern: #"&#(?:([0-9]+)|x([0-9A-Fa-f]+));"#
        ) else { return result }
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            let value: UInt32?
            if let decimalRange = Range(match.range(at: 1), in: result) {
                value = UInt32(String(result[decimalRange]))
            } else if let hexadecimalRange = Range(match.range(at: 2), in: result) {
                value = UInt32(String(result[hexadecimalRange]), radix: 16)
            } else {
                value = nil
            }
            guard let value, let scalar = UnicodeScalar(value) else { continue }
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: String(scalar))
        }
        return result
    }

    static func requiresFullReader(_ document: LeonardoDocument) -> Bool {
        guard document.metadata.layout?.objects.isEmpty != false,
              (try? LeonardoLocalImagePolicy.hasEmbeddedSigningImages(in: document)) == false else { return true }
        return document.metadata.fields.contains { id, field in
            guard field.type == .rubric, field.signerPosition == nil,
                  let value = document.metadata.values[id] ?? field.defaultValue else { return false }
            if case .object = value { return true }
            return false
        }
    }

    static func referencedResourceReferences(from document: LeonardoDocument) -> Set<String> {
        Set((try? LeonardoLocalImagePolicy.signingReferences(in: document)) ?? [])
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
    let spanish: Bool
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
            && !MobileGuidedSigningNativeContent.requiresFullReader(document)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        spanish ? "Vista de texto" : "Text view",
                        systemImage: "text.book.closed"
                    )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileClassic.secondary)
                    Text(document.metadata.document.title ?? (spanish ? "Copia de firma" : "Signing copy"))
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
                        Text(spanish ? "Recursos sellados" : "Sealed resources")
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
                                        spanish ? "Este recurso no se puede mostrar aquí; la confirmación queda bloqueada." : "This resource cannot be shown here; confirmation is blocked.",
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
                                spanish ? "Falta el recurso sellado \(reference); la confirmación queda bloqueada." : "Sealed resource \(reference) is missing; confirmation is blocked.",
                                systemImage: "exclamationmark.triangle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    }

                    if !nativeContentComplete {
                        Label(
                            spanish ? "La lectura nativa no representa todo el material sellado; no se puede confirmar hasta mostrarlo." : "The native reader does not represent all sealed material; confirmation is blocked until it is shown.",
                            systemImage: "lock.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("mobile-signing-native-content-incomplete")
                    }

                    if !targets.isEmpty {
                        Divider()
                        Text(spanish ? "Apariciones exactas" : "Exact occurrences")
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
                            spanish ? "No hay apariciones exactas disponibles; la confirmación permanece bloqueada." : "No exact occurrences are available; confirmation remains blocked.",
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
        target.reviewedContext(in: document.body)?.replacingOccurrences(of: "\n", with: " ↵ ") ?? ""
    }
}
