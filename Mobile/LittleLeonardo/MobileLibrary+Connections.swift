import Foundation

extension MobileLibrary {
    @discardableResult
    func renameConnection(connectionID: UUID, displayName: String) -> Bool {
        guard let index = connections.firstIndex(where: { $0.connectionID == connectionID }) else {
            error = MobileErrorNotice.record(
                operation: .pairing,
                message: "No se encontró la conexión con ese Mac.",
                category: "connection_not_found")
            return false
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 80 else {
            error = MobileErrorNotice.record(
                operation: .pairing,
                message: "El nombre del Mac no puede superar 80 caracteres.",
                category: "display_name_too_long")
            return false
        }
        var updated = connections
        updated[index].displayName = trimmed.isEmpty ? nil : trimmed
        do {
            try connectionStore.save(updated)
            connections = updated
            return true
        } catch {
            presentError(error, operation: .library,
                         message: "No se pudo guardar el nombre del Mac. Inténtalo de nuevo.")
            return false
        }
    }
}
