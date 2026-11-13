import Foundation

extension MobileLibrary {
    @discardableResult
    func renameConnection(connectionID: UUID, displayName: String) -> Bool {
        guard let index = connections.firstIndex(where: { $0.connectionID == connectionID }) else {
            error = "No se encontró la conexión con ese Mac."
            return false
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80 else {
            error = "El nombre del Mac no puede superar 80 caracteres."
            return false
        }
        var updated = connections
        updated[index].displayName = trimmed.isEmpty ? nil : trimmed
        do {
            try connectionStore.save(updated)
            connections = updated
            return true
        } catch {
            self.error = "No se pudo guardar el nombre del Mac: \(error.localizedDescription)"
            return false
        }
    }
}
