import Foundation

struct MobileConnectionToken: Sendable {
    let connectionID: UUID
    let deviceID: UUID
    let fingerprint: Data
    let cacheEpoch: UInt64
    let authorizationGeneration: UInt64
}

struct MobileAuthorizationGenerations {
    private var values: [UUID: UInt64] = [:]

    subscript(connectionID: UUID) -> UInt64 { values[connectionID, default: 0] }

    mutating func invalidate(connectionID: UUID) {
        values[connectionID, default: 0] &+= 1
    }
}
