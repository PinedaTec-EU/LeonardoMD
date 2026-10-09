import Foundation

/// Why a mobile Git commit is being published.
///
/// A normal publication carries changed selected files. A reconciliation
/// request deliberately carries a clean snapshot so the desktop can review a
/// source-branch conflict even when the mobile corpus has no new bytes.
public enum GitPublicationPurpose: String, Codable, Equatable, Sendable {
    case normalChanges
    case reconciliationRequest
}
