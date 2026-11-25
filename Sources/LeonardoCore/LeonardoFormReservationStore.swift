import Foundation

/// Mac-side storage shared by the editor and the sync helper. The response
/// and reservation state are committed together so a lost acknowledgement
/// can be recovered without creating a second response.
public struct LeonardoFormReservationStore: Sendable {
    public struct Reservation: Codable, Equatable, Sendable {
        public let id: UUID
        public let deviceID: UUID
        public let revision: String

        public init(id: UUID, deviceID: UUID, revision: String) {
            self.id = id
            self.deviceID = deviceID
            self.revision = revision
        }
    }

    public enum Failure: Error {
        case busy
        case inactive
        case revoked
        case revisionChanged
        case conflictingRetry
        case invalidStorage
    }

    public enum Status: Sendable {
        case active, cancelled, revoked, completed
    }

    private enum State: Codable {
        case active(Reservation)
        case cancelled(Reservation)
        case revoked(Reservation)
        case completed(Reservation, [String: LeonardoJSONValue], LeonardoDocument)

        var reservation: Reservation {
            switch self {
            case .active(let reservation), .cancelled(let reservation),
                 .revoked(let reservation), .completed(let reservation, _, _):
                reservation
            }
        }
    }

    private let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func activeReservation(for source: URL) throws -> Reservation? {
        try transaction(for: source) { folder in
            try active(in: folder)?.reservation
        }
    }

    public func status(of reservation: Reservation, for source: URL) throws -> Status {
        try transaction(for: source) { folder in
            let record = recordURL(for: reservation.id, in: folder)
            guard let state = try read(record), state.reservation == reservation else { throw Failure.inactive }
            switch state {
            case .active: return .active
            case .cancelled: return .cancelled
            case .revoked: return .revoked
            case .completed: return .completed
            }
        }
    }

    /// Must be called with a revision computed from the source and all of its
    /// resources. The callback also checks whether the editor has pending work.
    public func acquire(
        _ reservation: Reservation, for source: URL,
        inspectRevision: () throws -> String
    ) throws {
        try transaction(for: source) { folder in
            let record = recordURL(for: reservation.id, in: folder)
            if let existing = try read(record) {
                guard existing.reservation == reservation else { throw Failure.inactive }
                if case .revoked = existing { throw Failure.revoked }
                guard case .active = existing else { throw Failure.inactive }
                return
            }
            guard try active(in: folder) == nil else { throw Failure.busy }
            guard try inspectRevision() == reservation.revision else { throw Failure.revisionChanged }
            try write(.active(reservation), to: record)
        }
    }

    public func cancel(_ reservation: Reservation, for source: URL) throws {
        try transaction(for: source) { folder in
            let record = recordURL(for: reservation.id, in: folder)
            guard let state = try read(record), state.reservation == reservation else { throw Failure.inactive }
            switch state {
            case .active:
                try write(.cancelled(reservation), to: record)
            case .cancelled:
                return
            case .revoked:
                throw Failure.revoked
            case .completed:
                throw Failure.inactive
            }
        }
    }

    /// The caller must authorize a host-owner action. A stale selection
    /// can revoke only the exact reservation shown at confirmation.
    public func forceRevoke(_ reservation: Reservation, for source: URL) throws {
        try transaction(for: source) { folder in
            let record = recordURL(for: reservation.id, in: folder)
            guard let state = try read(record), state.reservation == reservation else { throw Failure.inactive }
            switch state {
            case .active:
                try write(.revoked(reservation), to: record)
            case .revoked:
                return
            case .cancelled, .completed:
                throw Failure.inactive
            }
        }
    }

    public func finish(
        _ reservation: Reservation, for source: URL, values: [String: LeonardoJSONValue],
        inspectSource: () throws -> (revision: String, document: LeonardoDocument)
    ) throws -> LeonardoDocument {
        try transaction(for: source) { folder in
            let record = recordURL(for: reservation.id, in: folder)
            guard let state = try read(record), state.reservation == reservation else { throw Failure.inactive }
            switch state {
            case .active:
                let inspected = try inspectSource()
                guard inspected.revision == reservation.revision else { throw Failure.revisionChanged }
                let response = try inspected.document.makeFormResponse(applying: values)
                try write(.completed(reservation, values, response), to: record)
                return response
            case .cancelled:
                throw Failure.inactive
            case .revoked:
                throw Failure.revoked
            case .completed(_, let submittedValues, let response):
                guard values == submittedValues else { throw Failure.conflictingRetry }
                return response
            }
        }
    }

    /// Wrap every coordinated editor write in the same per-source transaction
    /// that is used to grant a reservation.
    public func withEditingAccess<T>(to source: URL, _ edit: () throws -> T) throws -> T {
        try transaction(for: source) { folder in
            guard try active(in: folder) == nil else { throw Failure.busy }
            return try edit()
        }
    }

    private func transaction<T>(for source: URL, _ operation: (URL) throws -> T) throws -> T {
        let folder = root.appendingPathComponent(ProcessFileLock.key(for: source), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let lock = try ProcessFileLock(at: folder.appendingPathComponent("lock"), wait: true)
        return try withExtendedLifetime(lock) { try operation(folder) }
    }

    private func active(in folder: URL) throws -> State? {
        let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        var result: State?
        for entry in entries where entry.pathExtension == "json" {
            if let state = try read(entry), case .active = state {
                guard result == nil else { throw Failure.invalidStorage }
                result = state
            }
        }
        return result
    }

    private func recordURL(for id: UUID, in folder: URL) -> URL {
        folder.appendingPathComponent(id.uuidString + ".json")
    }

    private func read(_ url: URL) throws -> State? {
        do {
            return try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        }
    }

    private func write(_ state: State, to url: URL) throws {
        try JSONEncoder().encode(state).write(to: url, options: .atomic)
    }
}
