import SwiftUI
import LeonardoSync

struct MobileLibraryView: View {
    @Bindable var library: MobileLibrary
    var body: some View {
        NavigationStack {
            List(library.projects, id: \.id) { project in
                NavigationLink {
                    MobileProjectView(library: library, projectID: project.id)
                } label: {
                    VStack(alignment: .leading) {
                        Text(project.name)
                        Text(project.mode == .direct ? "Consulta desde LeonardoMD" : "Edición mediante Git")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if library.projects.isEmpty {
                    ContentUnavailableView("Little Leonardo", systemImage: "book.closed",
                        description: Text("Tus proyectos sincronizados aparecerán aquí. La conexión con LeonardoMD está en desarrollo."))
                }
            }
            .navigationTitle("Little Leonardo")
            .refreshable { await library.reload() }
            .alert("No se pudo completar la operación", isPresented: Binding(
                get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
                Button("Aceptar") { library.error = nil }
            } message: { Text(library.error ?? "") }
        }
    }
}

struct MobileProjectView: View {
    let library: MobileLibrary
    let projectID: UUID
    @State private var newDocument = false
    @State private var documentName = ""
    @State private var deletingPath: String?
    private var project: OfflineProject? { library.projects.first { $0.id == projectID } }
    var body: some View {
        List {
            if let project {
                Section {
                    Text(project.mode == .direct ? "Disponible offline · Solo lectura" : "Disponible offline · Git")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Carpeta: \(project.scope.folder.isEmpty ? "/" : project.scope.folder)")
                        .font(.caption)
                }
                ForEach(project.files.filter { ["md", "markdown", "txt"].contains(($0.path as NSString).pathExtension.lowercased()) }, id: \.path) { file in
                    NavigationLink(file.path) {
                        MobileDocumentView(library: library, projectID: project.id, file: file, mode: project.mode)
                    }.swipeActions {
                        if project.mode == .git {
                            Button("Eliminar", role: .destructive) { deletingPath = file.path }
                        }
                    }
                }
            }
        }.navigationTitle(project?.name ?? "Proyecto")
        .toolbar {
            if project?.mode == .git { Button("Nuevo documento", systemImage: "doc.badge.plus") { newDocument = true } }
        }
        .alert("Nuevo documento", isPresented: $newDocument) {
            TextField("Nombre.md", text: $documentName)
            Button("Crear") {
                guard let project else { return }
                let path = project.scope.folder.isEmpty ? documentName : project.scope.folder + "/" + documentName
                Task {
                    if await library.createDocument(projectID: projectID, path: path) { documentName = "" }
                }
            }
            Button("Cancelar", role: .cancel) { documentName = "" }
        } message: { Text("Se creará dentro de la carpeta autorizada del proyecto.") }
        .alert("Eliminar documento", isPresented: Binding(get: { deletingPath != nil }, set: { if !$0 { deletingPath = nil } })) {
            Button("Eliminar", role: .destructive) {
                guard let path = deletingPath else { return }
                Task { _ = await library.deleteFile(projectID: projectID, path: path) }
                deletingPath = nil
            }
            Button("Cancelar", role: .cancel) { deletingPath = nil }
        } message: { Text(deletingPath ?? "") }
    }
}

struct MobileDocumentView: View {
    let library: MobileLibrary
    let projectID: UUID
    let file: CorpusFile
    let mode: SyncMode
    @State private var text = ""
    @State private var editing = false
    @State private var readOnlyNotice = false
    @State private var saving = false

    var body: some View {
        Group {
            if editing { TextEditor(text: $text).font(.system(.body, design: .monospaced)).padding() }
            else {
                ScrollView {
                    Text(text).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
        }
        .navigationTitle((file.path as NSString).lastPathComponent)
        .toolbar {
            Button(editing ? "Guardar" : "Editar") {
                if editing {
                    saving = true
                    Task {
                        if await library.saveText(projectID: projectID, path: file.path, text: text) { editing = false }
                        saving = false
                    }
                } else if mode == .direct { readOnlyNotice = true }
                else { editing = true }
            }.disabled(saving || String(data: file.content, encoding: .utf8) == nil)
        }
        .onAppear { text = String(data: file.content, encoding: .utf8) ?? "Este documento no tiene una codificación UTF-8 válida." }
        .alert("Este proyecto es de solo lectura", isPresented: $readOnlyNotice) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text("Para editar y enviar cambios desde Little Leonardo, crea un repositorio Git y conecta el proyecto mediante Git.")
        }
    }
}
