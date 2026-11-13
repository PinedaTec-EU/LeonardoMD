import Foundation
import Observation

enum DocumentSearchScope: CaseIterable, Hashable, Identifiable, Sendable {
    case currentDocument
    case openDocuments

    var id: Self { self }
}

struct DocumentSearchMatch: Identifiable, Sendable {
    struct ID: Hashable, Sendable {
        let tabID: UUID
        let location: Int
        let length: Int
    }

    let id: ID
    let tabID: UUID
    let documentTitle: String
    let location: Int
    let length: Int

    var range: NSRange { NSRange(location: location, length: length) }
}

struct DocumentSearchSelection: Equatable {
    let range: NSRange
    let revision: Int
}

@MainActor @Observable
final class DocumentSearch {
    var isVisible = false
    var query = "" { didSet { criteriaDidChange(from: oldValue != query) } }
    var scope: DocumentSearchScope = .currentDocument { didSet { criteriaDidChange(from: oldValue != scope) } }
    var usesRegularExpression = false { didSet { criteriaDidChange(from: oldValue != usesRegularExpression) } }
    var matchCase = false { didSet { criteriaDidChange(from: oldValue != matchCase) } }

    private(set) var matches: [DocumentSearchMatch] = []
    private(set) var activeMatchID: DocumentSearchMatch.ID?
    private(set) var selectionRevision = 0
    private(set) var hasInvalidRegularExpression = false
    private(set) var isSearching = false

    @ObservationIgnored var criteriaDidChangeHandler: (@MainActor () -> Void)?
    @ObservationIgnored private var lastConfiguration: Configuration?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var workerTask: Task<DocumentSearchResult, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    var activeMatch: DocumentSearchMatch? {
        guard let activeMatchID else { return nil }
        return matches.first { $0.id == activeMatchID }
    }

    var activeMatchNumber: Int? {
        guard let activeMatchID else { return nil }
        return matches.firstIndex { $0.id == activeMatchID }.map { $0 + 1 }
    }

    var canNavigate: Bool { !isSearching && !matches.isEmpty }

    var statusMessage: String {
        if isSearching { return L10n.text("Searching…") }
        if hasInvalidRegularExpression { return L10n.text("Invalid regular expression") }
        guard !matches.isEmpty else {
            return query.isEmpty ? L10n.text("Type to search") : L10n.text("No matches")
        }
        if let number = activeMatchNumber, let activeMatch {
            return L10n.format("%d of %d · %@", number, matches.count, activeMatch.documentTitle)
        }
        return L10n.format("%d matches", matches.count)
    }

    func refresh(tabs: [DocumentTab], activeID: UUID?) {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        workerTask?.cancel()

        let effectiveActiveID = scope == .currentDocument ? activeID : nil
        let configuration = Configuration(query: query, scope: scope, usesRegularExpression: usesRegularExpression,
                                          matchCase: matchCase, activeTabID: effectiveActiveID)
        let resetSelection = configuration != lastConfiguration
        let previousMatchID = activeMatchID
        lastConfiguration = configuration

        if resetSelection, activeMatchID != nil {
            activeMatchID = nil
            selectionRevision &+= 1
        }

        guard !query.isEmpty else {
            matches = []
            hasInvalidRegularExpression = false
            isSearching = false
            if activeMatchID != nil {
                activeMatchID = nil
                selectionRevision &+= 1
            }
            return
        }

        let sources = tabs.compactMap { tab -> DocumentSearchSource? in
            guard tab.session.documentURL != nil,
                  scope == .openDocuments || tab.id == activeID else { return nil }
            return DocumentSearchSource(tabID: tab.id, documentTitle: tab.title, text: tab.session.content)
        }
        matches = []
        hasInvalidRegularExpression = false
        isSearching = true

        let input = DocumentSearchInput(query: query, usesRegularExpression: usesRegularExpression,
                                        matchCase: matchCase, sources: sources)
        let worker = Task { await DocumentSearchExecutor.shared.search(input) }
        workerTask = worker
        refreshTask = Task { [weak self, worker] in
            let result = await worker.value
            guard let self, !Task.isCancelled, self.refreshGeneration == generation else { return }
            self.matches = result.matches
            self.hasInvalidRegularExpression = result.hasInvalidRegularExpression
            self.isSearching = false

            if resetSelection {
                self.activeMatchID = nil
            } else if let previousMatchID, result.matches.contains(where: { $0.id == previousMatchID }) {
                self.activeMatchID = previousMatchID
            } else {
                self.activeMatchID = nil
            }
            if self.activeMatchID != previousMatchID { self.selectionRevision &+= 1 }
        }
    }

    func ranges(for tabID: UUID) -> [NSRange] {
        matches.filter { $0.tabID == tabID }.map(\.range)
    }

    func selection(for tabID: UUID) -> DocumentSearchSelection? {
        guard let activeMatch, activeMatch.tabID == tabID else { return nil }
        return DocumentSearchSelection(range: activeMatch.range, revision: selectionRevision)
    }

    @discardableResult
    func navigate(by offset: Int) -> DocumentSearchMatch? {
        guard canNavigate, offset == -1 || offset == 1 else { return nil }
        let nextIndex: Int
        if let activeIndex = activeMatchNumber.map({ $0 - 1 }) {
            nextIndex = (activeIndex + offset + matches.count) % matches.count
        } else {
            nextIndex = offset > 0 ? 0 : matches.count - 1
        }
        let match = matches[nextIndex]
        activeMatchID = match.id
        selectionRevision &+= 1
        return match
    }

    private func criteriaDidChange(from changed: Bool) {
        guard changed else { return }
        if activeMatchID != nil { selectionRevision &+= 1 }
        activeMatchID = nil
        criteriaDidChangeHandler?()
    }

    private struct Configuration: Equatable {
        let query: String
        let scope: DocumentSearchScope
        let usesRegularExpression: Bool
        let matchCase: Bool
        let activeTabID: UUID?
    }
}
