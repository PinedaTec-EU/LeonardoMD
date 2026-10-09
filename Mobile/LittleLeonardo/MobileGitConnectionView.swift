import SwiftUI

struct MobileGitConnectionView: View {
    let library: MobileLibrary
    @State private var enrollment = MobileGitEnrollment()
    @State private var operation: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if enrollment.discovery == nil { credentials }
                else if enrollment.metadata == nil { branches }
                else { folders }
                if enrollment.busy { ProgressView("Conectando con Git…") }
                if let error = enrollment.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Conectar mediante Git")
            .toolbar { Button("Cerrar") { operation?.cancel(); dismiss() } }
            .onDisappear { operation?.cancel() }
        }
    }

    private var credentials: some View {
        Section {
            Text("Git puede sincronizar fuera de tu red local. Primero elegiremos la rama y la carpeta; no se descargará el repositorio completo.")
            TextField("https://servidor/proyecto.git", text: $enrollment.endpointText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .accessibilityIdentifier("git-endpoint")
            TextField("Usuario (opcional)", text: $enrollment.username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Contraseña o token", text: $enrollment.password)
            Text("Las credenciales se guardan en el Keychain del dispositivo.").font(.caption)
            Button("Buscar ramas") { operation = Task { await enrollment.discover() } }
                .disabled(enrollment.busy || enrollment.endpointText.isEmpty).accessibilityIdentifier("git-discover")
        }.disabled(enrollment.busy)
    }

    private var branches: some View {
        Section("Elegir rama") {
            ForEach(enrollment.branches, id: \.name) { ref in
                Button(String(ref.name.dropFirst("refs/heads/".count))) {
                    operation = Task { await enrollment.selectBranch(ref) }
                }.disabled(enrollment.busy)
            }
        }
    }

    private var folders: some View {
        Section {
            Text("Rama: \(enrollment.branch.dropFirst("refs/heads/".count))").font(.caption)
            Text("Carpeta: \(enrollment.folder.isEmpty ? "/" : enrollment.folder)")
                .accessibilityIdentifier("git-selected-folder")
            if !enrollment.folder.isEmpty {
                Button("Subir una carpeta", systemImage: "arrow.up") {
                    enrollment.selectFolder(enrollment.folder.split(separator: "/").dropLast().joined(separator: "/"))
                }
            }
            ForEach(enrollment.folders, id: \.self) { folder in
                Button(folder, systemImage: "folder") {
                    enrollment.selectFolder(enrollment.folder.isEmpty ? folder : enrollment.folder + "/" + folder)
                }
            }
            TextField("Nombre del proyecto", text: $enrollment.projectName)
            Text("Solo se descargarán documentos y recursos compatibles dentro de esta carpeta. Los cambios se reconciliarán en LeonardoMD.").font(.caption)
            Button("Sincronizar esta carpeta") {
                operation = Task { if await enrollment.importProject(into: library) { dismiss() } }
            }.disabled(enrollment.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("git-import-folder")
            Button("Elegir otra rama") { enrollment.resetBranch() }
        }.disabled(enrollment.busy)
    }
}
