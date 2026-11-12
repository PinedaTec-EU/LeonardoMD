import AppKit

extension DocumentTabs {
    func refreshSearch() {
        search.refresh(tabs: tabs, activeID: activeID)
    }

    func presentSearch() {
        guard !closing else { return }
        if search.query.isEmpty,
           let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
           editor.accessibilityIdentifier() == "markdown-editor" {
            let selection = editor.selectedRange()
            let source = activeSession.content as NSString
            if selection.length > 0, NSMaxRange(selection) <= source.length {
                search.query = source.substring(with: selection)
            }
        }
        search.isVisible = true
        if search.query.isEmpty { refreshSearch() }
    }

    func dismissSearch() {
        search.isVisible = false
    }

    func navigateSearch(by offset: Int) {
        guard offset == -1 || offset == 1, !closing else { return }
        guard search.isVisible else {
            if search.query.isEmpty {
                presentSearch()
                return
            }
            search.isVisible = true
        }
        guard let match = search.navigate(by: offset),
              let target = tabs.first(where: { $0.id == match.tabID }) else { return }

        if activeID != target.id {
            select(target.id)
        }

        let session = target.session
        guard session.mode != .edit, session.mode != .split else { return }
        let documentURL = session.documentURL
        let selectionRevision = search.selectionRevision
        Task { [weak self, weak session] in
            guard let self, let session,
                  await session.flushPreviewEdits(),
                  !self.closing, !session.stopped,
                  session.documentURL == documentURL,
                  self.search.selectionRevision == selectionRevision else { return }
            session.mode = .edit
            session.selectedLeonardoFieldID = nil
        }
    }
}
