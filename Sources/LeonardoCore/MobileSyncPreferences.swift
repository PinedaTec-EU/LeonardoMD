import Foundation

public struct MobileSharedProject: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let rootURL: URL
    public let name: String
    public let folders: [String]
    public let documents: [String]
    public init(id: UUID = UUID(), rootURL: URL, name: String, folders: [String] = [""], documents: [String] = []) {
        self.id = id; self.rootURL = rootURL; self.name = name
        self.folders = folders; self.documents = documents
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(UUID.self, forKey: .id), rootURL: try values.decode(URL.self, forKey: .rootURL),
                  name: try values.decode(String.self, forKey: .name),
                  folders: try values.decodeIfPresent([String].self, forKey: .folders) ?? [""],
                  documents: try values.decodeIfPresent([String].self, forKey: .documents) ?? [])
    }

    private enum CodingKeys: String, CodingKey { case id, rootURL, name, folders, documents }
}

/// Installation-local settings, never part of portable project configuration.
public struct MobileSyncPreferences: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var host: String?
    public var port: UInt16
    public var projects: [MobileSharedProject]
    /// Explicit opt-in for a private overlay such as Tailscale's 100.64/10 range.
    /// LAN selection remains the default, including when this preference is absent
    /// in a legacy preferences file.
    public var privateOverlayEnabled: Bool

    public init(enabled: Bool = false, host: String? = nil, port: UInt16 = 40882,
                projects: [MobileSharedProject] = [], privateOverlayEnabled: Bool = false) {
        self.enabled = enabled; self.host = host; self.port = port; self.projects = projects
        self.privateOverlayEnabled = privateOverlayEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, host, port, projects, privateOverlayEnabled
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        host = try values.decodeIfPresent(String.self, forKey: .host)
        port = try values.decodeIfPresent(UInt16.self, forKey: .port) ?? 40882
        projects = try values.decodeIfPresent([MobileSharedProject].self, forKey: .projects) ?? []
        privateOverlayEnabled = try values.decodeIfPresent(Bool.self, forKey: .privateOverlayEnabled) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(enabled, forKey: .enabled)
        try values.encodeIfPresent(host, forKey: .host)
        try values.encode(port, forKey: .port)
        try values.encode(projects, forKey: .projects)
        try values.encode(privateOverlayEnabled, forKey: .privateOverlayEnabled)
    }
}
