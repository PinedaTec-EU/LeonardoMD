import Foundation
import LeonardoCore
import LeonardoSync

/// Shares one in-flight submission only when its complete immutable request
/// binding and frozen payload match. A request UUID alone is not sufficient:
/// a peer could otherwise attach a different request or drawing to a cached
/// operation and bypass the response conflict checks.
@MainActor
final class MobileRubricSubmissionGate {
    private struct ActiveSubmission {
        let request: RubricRequest
        let label: String
        let rubric: LeonardoRubric
        let task: Task<RubricResponse, Error>
    }

    private var active: [UUID: ActiveSubmission] = [:]

    func submit(request: RubricRequest, label: String, rubric: LeonardoRubric,
                operation: @escaping @MainActor () async throws -> RubricResponse) async throws -> RubricResponse {
        let cleanLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if let current = active[request.id] {
            guard current.request.matchesImmutableIdentity(request),
                  current.label == cleanLabel, current.rubric == rubric else {
                throw RubricExchangeError.conflict
            }
            return try await current.task.value
        }

        let task = Task { @MainActor in try await operation() }
        active[request.id] = ActiveSubmission(request: request, label: cleanLabel,
                                               rubric: rubric, task: task)
        defer { active.removeValue(forKey: request.id) }
        return try await task.value
    }
}
