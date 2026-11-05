#if os(macOS)
import Foundation
import Security

/// Bind both identifiers and the Developer ID team. Trusting an arbitrary parent
/// bundle's requirement would let a copied helper accept a different application.
public enum SyncHelperSigning {
    public static func requirement(for url: URL, identifier: String, matching ownerURL: URL) throws -> String {
        let peer = try signedCode(url)
        let owner = try signedCode(ownerURL)
        try validate(identifier: peer.identifier, team: peer.team, expectedIdentifier: identifier, ownerTeam: owner.team)
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(peer.code, [], &requirement) == errSecSuccess, let requirement else {
            throw SyncHelperFailure("The sync component has no signing requirement.")
        }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            throw SyncHelperFailure("Cannot verify the sync component identity.")
        }
        return text as String
    }

    static func validate(identifier: String?, team: String?, expectedIdentifier: String, ownerTeam: String?) throws {
        guard identifier == expectedIdentifier, let team, !team.isEmpty, team == ownerTeam else {
            throw SyncHelperFailure("Leonardo Sync requires matching Developer ID signed app and helper components.")
        }
    }

    private static func signedCode(_ url: URL) throws -> (code: SecStaticCode, identifier: String?, team: String?) {
        var developerID: SecRequirement?
        let requirement = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecRequirementCreateWithString(requirement as CFString, [], &developerID) == errSecSuccess,
              let developerID else { throw SyncHelperFailure("Cannot verify Developer ID signing.") }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), developerID) == errSecSuccess else {
            throw SyncHelperFailure("The sync component has an invalid code signature.")
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else {
            throw SyncHelperFailure("Cannot read the sync component identity.")
        }
        return (code, values[kSecCodeInfoIdentifier as String] as? String,
                values[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}
#endif
