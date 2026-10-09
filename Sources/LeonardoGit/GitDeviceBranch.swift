import Foundation

public enum GitDeviceBranch {
    public static func name(deviceID: UUID, projectID: UUID) -> String {
        "refs/heads/little-leonardo/\(deviceID.uuidString.lowercased())/\(projectID.uuidString.lowercased())"
    }
}
