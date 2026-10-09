import Foundation

public enum DesktopPeerWorkspaceError: Error, Equatable, Sendable {
    case busy
    case unknownCopy
    case existingCopyMismatch
    case missingWorkingDirectory
}

public protocol DesktopPeerWorkspaceAccess: Sendable {
    func install(_ copy: DesktopPeerCopy) async throws -> URL
    func open(id: UUID) async throws -> URL
    func capture(id: UUID, buffers: [OpenDocumentBuffer]) async throws -> DesktopPeerCopy
    func remove(id: UUID) async throws
}
