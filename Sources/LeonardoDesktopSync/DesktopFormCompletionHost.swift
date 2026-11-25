#if os(macOS)
import Foundation
import LeonardoCore
import LeonardoSync

public struct DesktopFormCompletionHost: RemoteFormCompletionHosting {
    private let reservations: LeonardoFormReservationStore
    private let checkEditor: @Sendable (URL) throws -> Void

    public init(reservations: LeonardoFormReservationStore, checkEditor: @escaping @Sendable (URL) throws -> Void) {
        self.reservations = reservations
        self.checkEditor = checkEditor
    }

    public func handle(_ command: RemoteFormCompletionCommand, deviceID: UUID,
                       source: SharedProjectSource) throws -> RemoteFormCompletionReceipt {
        guard let root = source.rootURL else { throw RemoteFormCompletionError.unsupported }
        let url = try source.descriptor.scope.fileURL(for: command.path, under: root)
        let reservation = LeonardoFormReservationStore.Reservation(id: command.sessionID, deviceID: deviceID,
                                                                     revision: command.revision)
        func inspect() throws -> RemoteFormSource {
            try RemoteFormSource(file: read(command.path, source: source, root: root)) {
                try read($0, source: source, root: root)
            }
        }
        let state: RemoteFormCompletionReceipt.State
        do {
            switch command.action {
            case .acquire:
                try reservations.acquire(reservation, for: url) {
                    try checkEditor(url)
                    return try inspect().revision
                }
                state = .active
            case .status:
                switch try reservations.status(of: reservation, for: url) {
                case .active: state = .active
                case .completed: state = .completed
                case .cancelled: state = .cancelled
                case .revoked: state = .revoked
                }
            case .cancel:
                try reservations.cancel(reservation, for: url)
                state = .cancelled
            case .finish:
                guard let values = command.values else { throw RemoteFormCompletionError.invalidCommand }
                _ = try reservations.finish(reservation, for: url, values: values) {
                    let current = try inspect()
                    return (current.revision, current.document)
                }
                state = .completed
            }
        } catch LeonardoFormReservationStore.Failure.revoked {
            state = .revoked
        } catch LeonardoFormReservationStore.Failure.busy {
            throw RemoteFormCompletionError.busy
        } catch LeonardoFormReservationStore.Failure.inactive {
            throw RemoteFormCompletionError.inactive
        } catch LeonardoFormReservationStore.Failure.revisionChanged {
            throw RemoteFormCompletionError.staleRevision
        } catch LeonardoFormReservationStore.Failure.conflictingRetry {
            throw RemoteFormCompletionError.invalidResponse
        } catch is LeonardoFormResponseError {
            throw RemoteFormCompletionError.invalidResponse
        }
        return RemoteFormCompletionReceipt(sessionID: command.sessionID, state: state)
    }

    private func read(_ path: String, source: SharedProjectSource, root: URL) throws -> CorpusFile {
        try source.descriptor.selection?.validate(path)
        let url = try source.descriptor.scope.fileURL(for: path, under: root)
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        let maximumBytes = CorpusLimits().maximumFileBytes
        guard attributes.isRegularFile == true, let size = attributes.fileSize, size <= maximumBytes else {
            throw SyncError.sizeLimitExceeded
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard bytes.count == size else { throw RemoteFormCompletionError.staleRevision }
        return CorpusFile(path: path, content: bytes)
    }
}
#endif
