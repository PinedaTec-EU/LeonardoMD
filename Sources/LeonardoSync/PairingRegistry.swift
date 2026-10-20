import Foundation
import CryptoKit
import Security

public enum PairingError: Error, Equatable, Sendable {
    case disabled, invalidCredential, expiredInvitation, pendingApproval, unknownDevice, invalidProject
    case randomGenerationFailed
}

public struct PairingInvitation: Codable, Equatable, Sendable {
    public let id: UUID
    public let secret: String
    public let expiresAt: Date
}

public enum PairingClientKind: String, Codable, Equatable, Sendable { case readOnly, desktopPeer }

public struct PairingRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let deviceName: String
    public let comparisonCode: String
    public let expiresAt: Date
    public let credentialDigest: Data
    public let kind: PairingClientKind

    init(id: UUID, deviceName: String, comparisonCode: String, expiresAt: Date, credentialDigest: Data, kind: PairingClientKind) {
        self.id = id; self.deviceName = deviceName; self.comparisonCode = comparisonCode
        self.expiresAt = expiresAt; self.credentialDigest = credentialDigest; self.kind = kind
    }
    private enum CodingKeys: String, CodingKey { case id, deviceName, comparisonCode, expiresAt, credentialDigest, kind }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(UUID.self, forKey: .id), deviceName: c.decode(String.self, forKey: .deviceName),
                  comparisonCode: c.decode(String.self, forKey: .comparisonCode), expiresAt: c.decode(Date.self, forKey: .expiresAt),
                  credentialDigest: c.decode(Data.self, forKey: .credentialDigest), kind: c.decodeIfPresent(PairingClientKind.self, forKey: .kind) ?? .readOnly)
    }
}

public struct PairedDevice: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let credentialDigest: Data
    public let projects: Set<UUID>
    public var revoked: Bool
    public let kind: PairingClientKind

    init(id: UUID, name: String, credentialDigest: Data, projects: Set<UUID>, revoked: Bool, kind: PairingClientKind) {
        self.id = id; self.name = name; self.credentialDigest = credentialDigest
        self.projects = projects; self.revoked = revoked; self.kind = kind
    }
    private enum CodingKeys: String, CodingKey { case id, name, credentialDigest, projects, revoked, kind }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(UUID.self, forKey: .id), name: c.decode(String.self, forKey: .name),
                  credentialDigest: c.decode(Data.self, forKey: .credentialDigest), projects: c.decode(Set<UUID>.self, forKey: .projects),
                  revoked: c.decode(Bool.self, forKey: .revoked), kind: c.decodeIfPresent(PairingClientKind.self, forKey: .kind) ?? .readOnly)
    }
}

public enum DeviceAccess: String, Codable, Equatable, Sendable { case authorized, revoked, pending }

/// Pure consent policy. The transport must encrypt all requests and verify the server identity.
/// Only digests are retained; bearer credentials and invitation secrets belong in secure storage.
public struct PairingRegistry: Codable, Sendable {
    public private(set) var enabled = false
    public private(set) var devices: [PairedDevice] = []
    public private(set) var requests: [PairingRequest] = []
    private var invitations: [UUID: InvitationRecord] = [:]
    private static let invitationLifetime: TimeInterval = 300
    private static let requestLifetime: TimeInterval = 300
    private static let maximumPendingRequests = 32

    private struct InvitationRecord: Codable, Sendable {
        let digest: Data
        let expiresAt: Date
    }

    public init() {}

    public mutating func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { invitations.removeAll(); requests.removeAll() }
    }

    public mutating func createInvitation(now: Date) throws -> PairingInvitation {
        guard enabled else { throw PairingError.disabled }
        expire(now: now)
        let invitation = PairingInvitation(id: UUID(), secret: try Self.makeCredential(),
                                          expiresAt: now.addingTimeInterval(Self.invitationLifetime))
        // A newly displayed QR invalidates the previous QR; linked devices are unaffected.
        invitations = [invitation.id: InvitationRecord(digest: Self.digest(invitation.secret), expiresAt: invitation.expiresAt)]
        return invitation
    }

    public mutating func requestPairing(deviceName: String, credential: String,
                                       invitation: PairingInvitation? = nil, serverFingerprint: Data, now: Date, kind: PairingClientKind = .readOnly) throws -> PairingRequest {
        guard enabled else { throw PairingError.disabled }
        expire(now: now)
        guard credential.count == 64, credential.allSatisfy(\.isHexDigit),
              !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              deviceName.count <= 100, requests.count < Self.maximumPendingRequests else {
            throw PairingError.invalidCredential
        }
        if let invitation {
            guard let record = invitations[invitation.id], record.expiresAt > now,
                  Self.matches(record.digest, Self.digest(invitation.secret)) else { throw PairingError.expiredInvitation }
            invitations.removeValue(forKey: invitation.id)
        }
        let credentialDigest = Self.digest(credential)
        guard !devices.contains(where: { Self.matches($0.credentialDigest, credentialDigest) }),
              !requests.contains(where: { Self.matches($0.credentialDigest, credentialDigest) }) else {
            throw PairingError.invalidCredential
        }
        let id = UUID()
        let code = try PairingComparisonCode.make(serverFingerprint: serverFingerprint, credential: credential, requestID: id, kind: kind)
        let request = PairingRequest(id: id, deviceName: deviceName,
            comparisonCode: code, expiresAt: now.addingTimeInterval(Self.requestLifetime),
            credentialDigest: credentialDigest, kind: kind)
        requests.append(request)
        return request
    }

    /// Called only by the desktop UI after the user compares both displayed codes.
    public mutating func approve(requestID: UUID, comparisonCode: String, projects: Set<UUID>, now: Date) throws -> PairedDevice {
        guard enabled else { throw PairingError.disabled }
        expire(now: now)
        guard let request = requests.first(where: { $0.id == requestID }),
              request.comparisonCode == comparisonCode else { throw PairingError.pendingApproval }
        guard !projects.isEmpty else { throw PairingError.invalidProject }
        let device = PairedDevice(id: request.id, name: request.deviceName, credentialDigest: request.credentialDigest,
                                  projects: projects, revoked: false, kind: request.kind)
        devices.append(device)
        requests.removeAll { $0.id == requestID }
        return device
    }

    public mutating func reject(requestID: UUID) { requests.removeAll { $0.id == requestID } }

    public mutating func revoke(deviceID: UUID) throws {
        guard let index = devices.firstIndex(where: { $0.id == deviceID }) else { throw PairingError.unknownDevice }
        devices[index].revoked = true
    }

    /// Revocation status is available to the matching device solely to trigger local cleanup.
    public func access(deviceID: UUID, credential: String, projectID: UUID? = nil) throws -> DeviceAccess {
        guard enabled else { throw PairingError.disabled }
        guard let device = devices.first(where: { $0.id == deviceID }),
              Self.matches(device.credentialDigest, Self.digest(credential)) else { throw PairingError.invalidCredential }
        if device.revoked { return .revoked }
        if let projectID, !device.projects.contains(projectID) { throw PairingError.invalidProject }
        return .authorized
    }

    /// Proposal permission is consented at enrollment and cannot be self-upgraded later.
    public func authorizeReconciliation(deviceID: UUID, credential: String, projectID: UUID) throws {
        guard try access(deviceID: deviceID, credential: credential, projectID: projectID) == .authorized else { throw SyncError.revoked }
        guard devices.first(where: { $0.id == deviceID })?.kind == .desktopPeer else { throw SyncError.readOnly }
    }

    public func pairingStatus(requestID: UUID, credential: String, now: Date) throws -> DeviceAccess {
        if devices.contains(where: { $0.id == requestID }) { return try access(deviceID: requestID, credential: credential) }
        guard enabled else { throw PairingError.disabled }
        guard let request = requests.first(where: { $0.id == requestID && $0.expiresAt > now }),
              Self.matches(request.credentialDigest, Self.digest(credential)) else { throw PairingError.invalidCredential }
        return .pending
    }

    public static func makeCredential() throws -> String {
        try randomBytes(count: 32).map { String(format: "%02x", $0) }.joined()
    }

    private mutating func expire(now: Date) {
        invitations = invitations.filter { $0.value.expiresAt > now }
        requests.removeAll { $0.expiresAt <= now }
    }

    private static func digest(_ secret: String) -> Data { Data(SHA256.hash(data: Data(secret.utf8))) }

    private static func matches(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func randomBytes(count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        guard status == errSecSuccess else { throw PairingError.randomGenerationFailed }
        return bytes
    }
}
