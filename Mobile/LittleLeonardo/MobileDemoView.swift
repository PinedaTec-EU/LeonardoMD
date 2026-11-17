import SwiftUI
import LeonardoCore
import LeonardoRender

@MainActor
private final class MobileDemoSourceState {
    var value = ""
    var isActive = false
}

@MainActor
struct MobileDemoView: View {
    let language: MobileDemoStore.Language
    private let store = MobileDemoStore()
    private let documentIdentity: MobileDocumentIdentity
    @ObservedObject private var preferences: MobileMarkdownPreferences
    @StateObject private var recommendations: MobileExtensionRecommendations
    @State private var sourceState: MobileDemoSourceState
    @State private var content = ""
    @State private var source = false
    @State private var error: MobileErrorNotice?
    @State private var fieldHelp: String?
    @State private var saved = false
    @State private var confirmingReset = false
    @StateObject private var controller: MarkdownPreviewController
    @Environment(\.scenePhase) private var scenePhase

    init(language: MobileDemoStore.Language) {
        self.language = language
        let documentIdentity = MobileDocumentIdentity(
            projectID: MobileDemoStore.recommendationProjectID,
            path: "Demo-\(language.rawValue).mdlr")
        self.documentIdentity = documentIdentity
        let preferences = MobileMarkdownPreferences.shared
        let recommendations = MobileExtensionRecommendations()
        let sourceState = MobileDemoSourceState()
        let controller = MarkdownPreviewController()
        controller.onDetectedExtensions = { detectedSource, identifiers in
            guard sourceState.isActive, detectedSource == sourceState.value else { return }
            recommendations.activate(document: documentIdentity, preferences: preferences)
            recommendations.inspect(document: documentIdentity, source: detectedSource,
                                    detectedIDs: identifiers, preferences: preferences)
        }
        _preferences = ObservedObject(wrappedValue: preferences)
        _recommendations = StateObject(wrappedValue: recommendations)
        _sourceState = State(wrappedValue: sourceState)
        _controller = StateObject(wrappedValue: controller)
    }

    private var configuration: MarkdownPreviewConfiguration {
        let features = preferences.features
        var configuration = MarkdownPreviewConfiguration(
            allowsMermaid: features.mermaidEnabled,
            allowsMath: features.mathEnabled,
            allowsVegaLite: features.vegaLiteEnabled,
            allowsCitations: features.citationsEnabled,
            allowsMarkdownExtensions: features.markdownExtensionsEnabled,
            externalLinkPolicy: .blocked,
            appearance: .leonardoClassic, localAssetRoot: store.resources, allowsRemoteImages: false)
        configuration.allowsLeonardoFormat = true
        configuration.allowsFormFilling = true
        return configuration
    }

    var body: some View {
        Group {
            if content.isEmpty {
                ContentUnavailableView("Demo", systemImage: "doc", description: Text("No se pudo abrir / Could not open"))
            } else if source {
                ScrollView {
                    Text(content).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            } else {
                MarkdownPreview(content: content, baseURL: store.resources,
                    configuration: configuration, controller: controller)
                    .sheet(item: Binding(
                        get: { recommendations.prompt },
                        set: { if $0 == nil { recommendations.dismissPrompt() } }
                    )) { request in
                        MobileExtensionRecommendationDialog(request: request, spanish: language == .es) { choice, enableSelected in
                            recommendations.respond(to: request, choice: choice, enableSelected: enableSelected,
                                                    preferences: preferences)
                        }
                    }
            }
        }
        .classicSurface()
        .navigationTitle(language == .es ? "Demo y práctica" : "Demo & practice")
        .toolbar {
            Button("Guardar / Save") {
                Task {
                    if await controller.flushEdits() {
                        do { try store.save(content, language: language); saved = true }
                        catch {
                            self.error = MobileErrorNotice.record(
                                error,
                                operation: .practice,
                                message: errorMessage("Could not save the practice. Try again.",
                                                     "No se pudo guardar la práctica. Inténtalo de nuevo."),
                                spanish: language == .es)
                        }
                    } else {
                        error = MobileErrorNotice.record(
                            operation: .practice,
                            message: errorMessage("Could not save the changes. Try again.",
                                                  "No se pudieron guardar los cambios. Inténtalo de nuevo."),
                            category: "practice_flush_failed",
                            spanish: language == .es)
                    }
                }
            }.disabled(content.isEmpty).accessibilityIdentifier("demo-save")
            Menu {
                Button(source ? "Ver documento / Preview" : "Ver texto / View source") {
                    Task {
                        guard await controller.flushEdits() else { return }
                        source.toggle()
                    }
                }
                .accessibilityIdentifier("demo-source")
                Button("Restablecer / Reset", role: .destructive) { confirmingReset = true }
                    .accessibilityIdentifier("demo-reset")
            } label: { Label("Opciones / Options", systemImage: "ellipsis.circle") }
            .accessibilityIdentifier("demo-options")
        }
        .safeAreaInset(edge: .bottom) {
            if saved { Text("Guardado en este dispositivo / Saved on this device").font(.caption).padding(8) }
        }
        .onAppear {
            sourceState.isActive = true
            recommendations.activate(document: documentIdentity, preferences: preferences)
        }
        .task {
            controller.onFieldHelp = { fieldID in
                guard let document = try? LeonardoFormatParser.parse(content),
                      let field = document.metadata.fields[fieldID] else { return }
                fieldHelp = field.helpText ?? field.label ?? fieldID
            }
            controller.onFormEdit = { expected, changes in
                guard expected == content else { return nil }
                do {
                    let document = try LeonardoFormatParser.parse(expected)
                    guard let updated = document.applyingFormValues(changes) else { return nil }
                    let replacement = try LeonardoFormatParser.serialize(updated)
                    try store.save(replacement, language: language)
                    sourceState.value = replacement
                    recommendations.documentContentWillReload(documentIdentity)
                    content = replacement
                    saved = false
                    return replacement
                } catch {
                    self.error = MobileErrorNotice.record(
                        error,
                        operation: .practice,
                        message: errorMessage("Could not save the practice.", "No se pudo guardar la práctica."),
                        spanish: language == .es)
                    return nil
                }
            }
            do {
                let loaded = try store.load(language)
                sourceState.value = loaded
                content = loaded
            }
            catch {
                self.error = MobileErrorNotice.record(
                    error,
                    operation: .practice,
                    message: errorMessage("Could not open the practice.", "No se pudo abrir la práctica."),
                    spanish: language == .es)
            }
        }
        .onDisappear {
            sourceState.isActive = false
            recommendations.deactivate(document: documentIdentity)
            controller.onFormEdit = nil
            controller.onFieldHelp = nil
        }
        .onChange(of: preferences.extensionWarningResetRevision) { _, _ in
            recommendations.warningPreferencesDidReset(preferences: preferences)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { _ = await controller.flushEdits() } }
        }
        .confirmationDialog("¿Borrar las respuestas de esta demo? / Clear this demo's answers?", isPresented: $confirmingReset) {
            Button("Restablecer / Reset", role: .destructive) {
                Task {
                    guard await controller.flushEdits() else { return }
                    do {
                        let replacement = try store.reset(language)
                        sourceState.value = replacement
                        recommendations.documentContentWillReload(documentIdentity)
                        content = replacement
                        saved = false
                    }
                    catch {
                        self.error = MobileErrorNotice.record(
                            error,
                            operation: .practice,
                            message: errorMessage("Could not reset the practice.", "No se pudo restablecer la práctica."),
                            spanish: language == .es)
                    }
                }
            }
        } message: { Text("Solo afecta al idioma seleccionado. / Only affects the selected language.") }
        .sheet(isPresented: Binding(get: { fieldHelp != nil }, set: { if !$0 { fieldHelp = nil } })) {
            VStack(spacing: 24) {
                Text(fieldHelp ?? "").padding()
                Button("Cerrar / Close") { fieldHelp = nil }
            }.classicSurface().presentationDetents([.medium])
        }
        .alert(MobileErrorNotice.alertTitle(spanish: language == .es), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button(MobileErrorNotice.acceptLabel(spanish: language == .es)) { error = nil }
        } message: { Text(error?.alertMessage ?? "") }
    }

    private func errorMessage(_ english: String, _ spanish: String) -> String {
        language == .es ? spanish : english
    }
}

/// The bundled material is browsed as one ordinary library project.
struct MobileDemoProjectView: View {
    var body: some View {
        List {
            Section {
                MobileProjectIdentityLabel(name: "Demo", identity: .local)
                Text("Práctica local · Sin conexión / Local practice · Offline")
                    .font(.caption).foregroundStyle(MobileClassic.secondary)
            }
            .listRowBackground(MobileClassic.inset)
            ForEach(MobileDemoStore.Language.allCases) { language in
                NavigationLink {
                    MobileDemoView(language: language)
                } label: {
                    Label("Demo-\(language.rawValue).mdlr · \(language.title)", systemImage: "doc.text")
                }
                .foregroundStyle(MobileClassic.heading)
                .accessibilityIdentifier("open-demo-\(language.rawValue)")
                .listRowBackground(MobileClassic.paper)
            }
        }
        .classicSurface()
        .navigationTitle("Demo")
    }
}
