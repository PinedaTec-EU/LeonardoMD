import Foundation

public enum TrashAvailability: Sendable {
    case available, unavailable, unknown
}

public enum FileDeletionMode: Sendable {
    case trash
    /// The caller has obtained explicit consent to irreversible deletion.
    case permanentlyConfirmed
}

public enum FileDeletionError: Error {
    case trashUnavailable
}

enum TrashSupport {
    static func availability(at url: URL, fileManager: FileManager) -> TrashAvailability {
        #if os(macOS)
        do {
            _ = try fileManager.url(for: .trashDirectory, in: .userDomainMask,
                                    appropriateFor: url, create: false)
            return .available
        } catch {
            // A missing directory may be created by trashItem. Permission and
            // transient errors also do not establish that Trash is unsupported.
            return isUnavailable(error) ? .unavailable : .unknown
        }
        #else
        return .unknown
        #endif
    }

    static func isUnavailable(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return error.code == CocoaError.featureUnsupported.rawValue
        }
        return error.domain == NSPOSIXErrorDomain
            && [Int(ENOTSUP), Int(EOPNOTSUPP)].contains(error.code)
    }
}
