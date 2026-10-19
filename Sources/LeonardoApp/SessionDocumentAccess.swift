import Foundation

struct PendingDocumentAccess {
    let url: URL
    var revoked = false
}

extension AppSession {
    func beginDocumentAccess(to url: URL) -> UUID {
        let id = UUID()
        pendingDocumentAccesses[id] = PendingDocumentAccess(url: url)
        fileOperationCount += 1
        return id
    }

    func finishDocumentAccess(_ id: UUID) {
        guard pendingDocumentAccesses.removeValue(forKey: id) != nil else { return }
        fileOperationCount -= 1
    }

    func documentAccessIsActive(_ id: UUID) -> Bool {
        !stopped && pendingDocumentAccesses[id]?.revoked == false
    }

    /// Cancel only pending loads under these roots. A tab may still own an
    /// unrelated draft, which revocation must not stop or clear.
    func revokeDocumentAccesses(under paths: [String]) -> Set<UUID> {
        let ids = Set(pendingDocumentAccesses.compactMap { id, access -> UUID? in
            let path = access.url.standardizedFileURL.resolvingSymlinksInPath().path
            return paths.contains { path == $0 || path.hasPrefix($0 + "/") } ? id : nil
        })
        for id in ids { pendingDocumentAccesses[id]?.revoked = true }
        return ids
    }

    func waitForDocumentAccesses(_ ids: Set<UUID>) async {
        while ids.contains(where: { pendingDocumentAccesses[$0] != nil }) {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}
