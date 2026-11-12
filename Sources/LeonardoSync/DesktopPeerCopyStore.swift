import Foundation

public protocol DesktopPeerCopyStore: Sendable {
    func copyIDs() async throws -> [UUID]
    func load(id: UUID) async throws -> DesktopPeerCopy?
    func save(_ copy: DesktopPeerCopy) async throws
    func remove(id: UUID) async throws
}
