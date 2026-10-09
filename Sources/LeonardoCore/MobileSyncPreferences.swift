import Foundation

public struct MobileSharedProject: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let rootURL: URL
    public let name: String
    public init(id: UUID = UUID(), rootURL: URL, name: String) {
        self.id = id; self.rootURL = rootURL; self.name = name
    }
}

/// Installation-local settings, never part of portable project configuration.
public struct MobileSyncPreferences: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var host: String?
    public var port: UInt16
    public var projects: [MobileSharedProject]
    public init(enabled: Bool = false, host: String? = nil, port: UInt16 = 40882, projects: [MobileSharedProject] = []) {
        self.enabled = enabled; self.host = host; self.port = port; self.projects = projects
    }
}
