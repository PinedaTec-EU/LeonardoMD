import SwiftUI
import AppKit

struct WorkspaceView: View {
    @Bindable var session: AppSession
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                if session.presentation.showsSidebar {
                    ProjectSidebar(session: session)
                    Divider()
                }
                documentArea.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(session.busy)
                if session.presentation.showsInspector {
                    Divider()
                    ExtensionInspector(session: session)
                }
            }
            Divider()
            statusBar
        }
        .modifier(SessionAppearance(session: session))
        .background(session.surfaceColor)
        .sheet(isPresented: $session.showWorkspace) { WorkspaceManager(session: session).modifier(SessionAppearance(session: session)) }
        .sheet(isPresented: $session.showPreferences) { PreferencesView(session: session).modifier(SessionAppearance(session: session)) }
        .sheet(isPresented: $session.showGit) { GitPanel(session: session).modifier(SessionAppearance(session: session)) }
        .alert("LeonardoMD", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("Aceptar") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .onChange(of: session.showFrontmatter) { _, value in UserDefaults.standard.set(value, forKey: "showFrontmatter") }
        .onChange(of: session.confirmExternalLinks) { _, value in UserDefaults.standard.set(value, forKey: "confirmExternalLinks") }
        .onChange(of: session.showHidden) { _, value in
            session.globalPreferences.showHiddenFiles = value
            session.persistSettings()
        }
        .task { await session.initialize() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                Button("Abrir documento…") { session.chooseDocument() }
                Button("Abrir proyecto…") { session.chooseProject() }
                Button("Espacios de trabajo…") { session.showWorkspace = true }
                if session.projectURL == nil, let url = session.documentURL {
                    Button("Abrir carpeta como proyecto") { Task { await session.openProject(url.deletingLastPathComponent()) } }
                }
                if session.projectURL != nil {
                    Button("Ver solo este documento") { Task { await session.detachProject() } }
                }
                if !session.recentProjects.isEmpty {
                    Divider()
                    ForEach(session.recentProjects, id: \.self) { url in
                        Button(url.lastPathComponent) { Task { await session.openProject(url) } }
                    }
                }
            } label: { Image(systemName: "folder").padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1))).shadow(color: .black.opacity(0.08), radius: 3, y: 2) }.menuStyle(.borderlessButton).frame(width: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.documentURL?.lastPathComponent ?? "LeonardoMD").font(.headline).lineLimit(1)
                Text(session.projectURL == nil ? "Visor de documento" : session.projectURL!.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if session.documentURL != nil {
                PremiumSelection(selection: $session.mode, options: DocumentMode.allCases, title: { $0.title })
                    .accessibilityLabel("Modo")
                    .accessibilityIdentifier("document-mode")
                Button { session.focus.toggle() } label: { Image(systemName: session.focus ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") }
                    .help(session.focus ? "Salir de foco" : "Modo foco")
                    .accessibilityIdentifier("focus-mode")
                Button { session.exportPDF() } label: { Image(systemName: "square.and.arrow.up") }.help("Exportar PDF")
            }
            Button { session.showInspector.toggle() } label: { Label("Extensiones", systemImage: "puzzlepiece.extension") }
                .accessibilityIdentifier("extensions-button")
        }
        .buttonStyle(PremiumButtonStyle(compact: true))
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
    }

    @ViewBuilder private var documentArea: some View {
        if session.documentURL == nil {
            VStack(spacing: 18) {
                Image(systemName: "doc.richtext").font(.system(size: 54, weight: .light)).foregroundStyle(session.accentColor)
                Text("Tus documentos, a tu manera.").font(.largeTitle.weight(.semibold))
                Text("Abre un Markdown para leerlo al instante\no una carpeta para trabajar con un proyecto.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                HStack {
                    Button("Abrir documento…") { session.chooseDocument() }.buttonStyle(PremiumButtonStyle(prominent: true))
                    Button("Abrir proyecto…") { session.chooseProject() }.buttonStyle(PremiumButtonStyle())
                }
                Button("Gestionar espacios de trabajo…") { session.showWorkspace = true }.buttonStyle(PremiumButtonStyle())
                Text("Local · Sin cuenta · Extensiones opcionales").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if session.externalConflict {
                    HStack {
                        Label("El archivo cambió fuera de LeonardoMD. Tu edición está protegida.", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Recargar") { Task { await session.reloadFromDisk() } }
                        Button("Guardar copia…") { session.saveCopy() }
                    }.padding(12).background(Color.orange.opacity(0.14))
                }
                switch session.mode {
                case .preview: session.preview
                case .edit: editor
                case .split:
                    HSplitView {
                        editor.frame(minWidth: 220)
                        session.preview.frame(minWidth: 220)
                    }
                }
            }
        }
    }
    private var editor: some View {
        MarkdownEditor(text: $session.content, scrollFraction: $session.editorScroll, requestedLine: session.requestedLine)
            .id(session.documentURL)
            .onChange(of: session.content) { _, _ in session.contentChanged() }
    }
    private var statusBar: some View {
        HStack {
            if session.busy { ProgressView().controlSize(.mini) }
            Label(session.saveStatus, systemImage: session.isDirty ? "circle.fill" : "checkmark.circle")
            Spacer()
            Text(session.focus ? "Foco" : session.projectURL == nil ? "Documento individual" : "Proyecto")
            Text("Markdown · UTF-8")
            Text("\(session.wordCount) palabras")
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 8)
    }
}
