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
    public init(enabled: Bool = false, host: String? = nil, port: UInt16 = 40882, projects: [MobileSharedProject] = []) {
        self.enabled = enabled; self.host = host; self.port = port; self.projects = projects
    }
}
