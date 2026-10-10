import SwiftUI
import UIKit
import LeonardoGit

struct MobileGitConnectionView: View {
    let library: MobileLibrary
    @State private var enrollment = MobileGitEnrollment()
    @State private var operation: Task<Void, Never>?
    @State private var publicKeyCopied = false
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
            TextField("https://servidor/proyecto.git o ssh://usuario@servidor/ruta.git", text: $enrollment.endpointText)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                .accessibilityIdentifier("git-endpoint")
            TextField("Usuario (opcional)", text: $enrollment.username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if isSSH {
                Picker("Tipo de clave", selection: $enrollment.sshKeyAlgorithm) {
                    ForEach(GitSSHKeyAlgorithm.allCases, id: \.self) { algorithm in
                        Text(algorithm.label).tag(algorithm)
                    }
                }
                Button("Generar clave SSH en este dispositivo") { enrollment.prepareSSHKeyIfNeeded() }
                if !enrollment.sshPublicKey.isEmpty {
                    Text("Publica esta clave en tu proveedor Git antes de buscar ramas:")
                        .font(.caption)
                    Text(enrollment.sshPublicKey)
                        .font(.system(.footnote, design: .monospaced))
                        .accessibilityIdentifier("git-public-key")
                        .textSelection(.enabled)
                    Button(publicKeyCopied ? "Clave pública copiada" : "Copiar clave pública") {
                        UIPasteboard.general.string = enrollment.sshPublicKey
                        publicKeyCopied = true
                    }
                    .accessibilityIdentifier("git-copy-public-key")
                }
                Text("Al terminar la conexión, la clave privada se guarda en el Keychain del dispositivo. Little Leonardo no importa claves OpenSSH privadas; puedes generar otra clave si cambias el tipo.")
                    .font(.caption)
            } else {
                SecureField("Contraseña o token", text: $enrollment.password)
                Text("Las credenciales se guardan en el Keychain del dispositivo.").font(.caption)
            }
            Button("Buscar ramas") { operation = Task { await enrollment.discover() } }
                .disabled(enrollment.busy || enrollment.endpointText.isEmpty).accessibilityIdentifier("git-discover")
            if let challenge = enrollment.hostKeyChallenge {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirma la identidad del servidor SSH").font(.headline)
                    Text("\(challenge.host):\(challenge.port) · \(challenge.algorithm)")
                    Text(challenge.fingerprint).font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Confirmar esta huella") {
                        operation = Task { await enrollment.confirmHostKey() }
                    }.disabled(enrollment.busy)
                        .accessibilityIdentifier("git-confirm-host-key")
                }
            }
        }.disabled(enrollment.busy)
    }

    private var isSSH: Bool {
        enrollment.isSSHEndpoint
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
                .accessibilityIdentifier("git-project-name")
            Text("Solo se descargarán documentos y recursos compatibles dentro de esta carpeta. Los cambios se reconciliarán en LeonardoMD.").font(.caption)
            Button("Sincronizar esta carpeta") {
                operation = Task { if await enrollment.importProject(into: library) { dismiss() } }
            }.disabled(enrollment.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("git-import-folder")
            Button("Elegir otra rama") { enrollment.resetBranch() }
        }.disabled(enrollment.busy)
    }
}
