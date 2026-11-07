import SwiftUI
import LeonardoCore
import LeonardoRender

struct MobileDemoView: View {
    let language: MobileDemoStore.Language
    private let store = MobileDemoStore()
    @State private var content = ""
    @State private var source = false
    @State private var error: String?
    @State private var fieldHelp: String?
    @State private var saved = false
    @State private var confirmingReset = false
    @StateObject private var controller = MarkdownPreviewController()
    @Environment(\.scenePhase) private var scenePhase

    private var configuration: MarkdownPreviewConfiguration {
        var configuration = MarkdownPreviewConfiguration(
            allowsMermaid: true, allowsMath: true, allowsVegaLite: true,
            allowsMarkdownExtensions: true, externalLinkPolicy: .blocked,
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
            }
        }
        .classicSurface()
        .navigationTitle(language == .es ? "Demo y práctica" : "Demo & practice")
        .toolbar {
            Button("Guardar / Save") {
                Task {
                    if await controller.flushEdits() {
                        do { try store.save(content, language: language); saved = true }
                        catch { self.error = error.localizedDescription }
                    } else { error = "No se pudo guardar / Could not save. Inténtalo de nuevo / Try again." }
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
                    content = replacement
                    saved = false
                    return replacement
                } catch { self.error = error.localizedDescription; return nil }
            }
            do { content = try store.load(language) }
            catch { self.error = error.localizedDescription }
        }
        .onDisappear {
            controller.onFormEdit = nil
            controller.onFieldHelp = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { _ = await controller.flushEdits() } }
        }
        .confirmationDialog("¿Borrar las respuestas de esta demo? / Clear this demo's answers?", isPresented: $confirmingReset) {
            Button("Restablecer / Reset", role: .destructive) {
                Task {
                    guard await controller.flushEdits() else { return }
                    do { content = try store.reset(language); saved = false }
                    catch { self.error = error.localizedDescription }
                }
            }
        } message: { Text("Solo afecta al idioma seleccionado. / Only affects the selected language.") }
        .sheet(isPresented: Binding(get: { fieldHelp != nil }, set: { if !$0 { fieldHelp = nil } })) {
            VStack(spacing: 24) {
                Text(fieldHelp ?? "").padding()
                Button("Cerrar / Close") { fieldHelp = nil }
            }.classicSurface().presentationDetents([.medium])
        }
        .alert("Demo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Aceptar / OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}
