import Foundation

/// The session scope that authorized a file action before a dialog or other suspension.
@MainActor
struct SessionFileOperationIdentity {
    let sourceURL: URL
    let projectURL: URL?
    let workspaceURL: URL?

    init(sourceURL: URL, session: AppSession) {
        self.sourceURL = sourceURL
        projectURL = session.projectURL
        workspaceURL = session.workspaceURL
    }

    func isCurrent(in session: AppSession) -> Bool {
        !session.stopped && !session.isClosing
            && session.projectURL == projectURL && session.workspaceURL == workspaceURL
    }
}
