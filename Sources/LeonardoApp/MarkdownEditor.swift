import AppKit
import SwiftUI

/// AppKit editor preserves native selection, undo and keyboard commands.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollFraction: Double
    var requestedLine: Int?
    var requestedLineRevision = 0
    var usesDocumentHistory = false
    var searchMatches: [NSRange] = []
    var activeSearchSelection: DocumentSearchSelection?
    var onUserScroll: ((Double) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        let editor = NSTextView()
        editor.isRichText = false
        editor.isEditable = context.environment.isEnabled
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.allowsUndo = !usesDocumentHistory
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textContainerInset = NSSize(width: 24, height: 24)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.string = text
        editor.setAccessibilityIdentifier("markdown-editor")
        scroll.hasVerticalScroller = true
        scroll.documentView = editor
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observe(scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        context.coordinator.applyingScroll = true
        defer {
            context.coordinator.programmaticOrigin = scroll.contentView.bounds.minY
            context.coordinator.applyingScroll = false
        }
        editor.isEditable = context.environment.isEnabled
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        if abs(scrollFraction - context.coordinator.lastScrollFraction) > 0.005 {
            context.coordinator.lastScrollFraction = scrollFraction
            let available = max(0, editor.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: available * scrollFraction))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        context.coordinator.expectedText = text
        if let line = requestedLine, line != context.coordinator.lastLine || requestedLineRevision != context.coordinator.lastLineRevision {
            context.coordinator.lastLine = line
            context.coordinator.lastLineRevision = requestedLineRevision
            let lines = text.components(separatedBy: "\n")
            let offset = lines.prefix(max(0, line - 1)).reduce(0) { $0 + ($1 as NSString).length + 1 }
            let range = NSRange(location: min(offset, (text as NSString).length), length: 0)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
        }
        context.coordinator.updateSearchHighlights(searchMatches, activeRange: activeSearchSelection?.range, in: editor)
        if let activeSearchSelection,
           context.coordinator.lastSearchSelectionRevision != activeSearchSelection.revision {
            let length = (editor.string as NSString).length
            let range = activeSearchSelection.range
            if range.location <= length, range.length <= length - range.location {
                editor.setSelectedRange(range)
                editor.scrollRangeToVisible(range)
            }
            context.coordinator.lastSearchSelectionRevision = activeSearchSelection.revision
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var expectedText: String
        var lastLine: Int?
        var lastLineRevision: Int?
        var applyingScroll = false
        var programmaticOrigin: CGFloat?
        var lastScrollFraction = 0.0
        var scrollObserver: NSObjectProtocol?
        var highlightedSearchRanges: [NSRange]?
        var highlightedActiveRange: NSRange?
        var lastSearchSelectionRevision: Int?
        init(_ parent: MarkdownEditor) { self.parent = parent; expectedText = parent.text }
        func textView(_ editor: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            guard parent.text == expectedText else {
                restoreSharedDraft(in: editor)
                return false
            }
            return true
        }
        private func restoreSharedDraft(in editor: NSTextView) {
            let selection = editor.selectedRange()
            expectedText = parent.text
            editor.string = expectedText
            editor.setSelectedRange(NSRange(location: min(selection.location, (expectedText as NSString).length), length: 0))
        }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            guard parent.text == expectedText else { restoreSharedDraft(in: editor); return }
            parent.text = editor.string
            expectedText = parent.text
            if editor.string != expectedText { restoreSharedDraft(in: editor) }
        }
        func updateSearchHighlights(_ ranges: [NSRange], activeRange: NSRange?, in editor: NSTextView) {
            guard ranges != highlightedSearchRanges || activeRange != highlightedActiveRange,
                  let layoutManager = editor.layoutManager else { return }
            let length = (editor.string as NSString).length
            guard length > 0 else {
                highlightedSearchRanges = ranges
                highlightedActiveRange = activeRange
                return
            }
            let fullRange = NSRange(location: 0, length: length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
            for range in ranges where range.location <= length && range.length <= length - range.location && range.length > 0 {
                layoutManager.addTemporaryAttribute(.backgroundColor,
                    value: NSColor.systemYellow.withAlphaComponent(0.48), forCharacterRange: range)
            }
            if let activeRange,
               activeRange.location <= length, activeRange.length <= length - activeRange.location {
                let visibleRange = activeRange.length == 0 && activeRange.location < length
                    ? NSRange(location: activeRange.location, length: 1) : activeRange
                if visibleRange.length > 0 {
                    layoutManager.addTemporaryAttribute(.backgroundColor,
                        value: NSColor.systemOrange.withAlphaComponent(0.72), forCharacterRange: visibleRange)
                }
            }
            layoutManager.invalidateDisplay(forCharacterRange: fullRange)
            highlightedSearchRanges = ranges
            highlightedActiveRange = activeRange
        }
        private func isUserScroll(in scroll: NSScrollView) -> Bool {
            guard let event = NSApp.currentEvent, event.window === scroll.window else { return false }
            switch event.type {
            case .scrollWheel:
                return scroll.bounds.contains(scroll.convert(event.locationInWindow, from: nil))
            case .leftMouseDown, .leftMouseDragged:
                guard let scroller = scroll.verticalScroller else { return false }
                return scroller.bounds.contains(scroller.convert(event.locationInWindow, from: nil))
            case .keyDown:
                return scroll.window?.firstResponder === scroll.documentView
            default:
                return false
            }
        }
        func observe(_ scroll: NSScrollView) {
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
            ) { [weak self, weak scroll] _ in
                MainActor.assumeIsolated {
                    guard let self, let scroll, let document = scroll.documentView else { return }
                    let available = max(1, document.bounds.height - scroll.contentView.bounds.height)
                    let fraction = min(1, max(0, scroll.contentView.bounds.minY / available))
                    self.lastScrollFraction = fraction
                    self.parent.scrollFraction = fraction
                    if !self.applyingScroll, self.programmaticOrigin != scroll.contentView.bounds.minY,
                       self.isUserScroll(in: scroll) {
                        self.parent.onUserScroll?(fraction)
                    }
                    self.programmaticOrigin = scroll.contentView.bounds.minY
                }
            }
        }
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.scrollObserver { NotificationCenter.default.removeObserver(observer) }
    }
}
