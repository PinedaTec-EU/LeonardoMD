#if os(macOS)
import Foundation
import Security

/// Use the packaged peer's designated requirement: Developer ID builds retain
/// identity across updates; ad-hoc QA builds remain bound to their exact code.
public enum SyncHelperSigning {
    public static func requirement(for url: URL) throws -> String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
            throw SyncHelperFailure("The sync component has an invalid code signature.")
        }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else {
            throw SyncHelperFailure("The sync component has no signing requirement.")
        }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else {
            throw SyncHelperFailure("Cannot verify the sync component identity.")
        }
        return text as String
    }
}
#endif
