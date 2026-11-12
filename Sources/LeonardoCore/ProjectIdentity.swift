import Foundation

/// Presentation from the current device's perspective, independent of connection health.
public enum ProjectIdentity: CaseIterable, Equatable, Sendable {
    case local, sharedFromThisDevice, received, recoveryArchive, unknown

    public static let projectSymbolName = "square.stack.3d.up"

    /// Incoming sharing is implicit in `received`; never add a second sharing badge.
    public var indicatorSymbolName: String? {
        switch self {
        case .sharedFromThisDevice: "person.2"
        case .received: "network"
        case .local, .recoveryArchive, .unknown: nil
        }
    }

    public func title(languageCode: String) -> String {
        let spanish = languageCode.lowercased().split(separator: "-").first == "es"
        switch self {
        case .local: return "Local"
        case .sharedFromThisDevice: return spanish ? "Compartido desde este equipo" : "Shared from this device"
        case .received: return spanish ? "Recibido de otro equipo" : "Received from another device"
        case .recoveryArchive: return spanish ? "Archivo de recuperación" : "Recovery archive"
        case .unknown: return spanish ? "Proyecto" : "Project"
        }
    }
}
