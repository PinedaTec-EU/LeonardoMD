import AppKit
import SwiftUI

/// AppKit editor preserves native selection, undo and keyboard commands.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var scrollFraction: Double
    var requestedLine: Int?

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
        editor.allowsUndo = true
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
        if let line = requestedLine, line != context.coordinator.lastLine {
            context.coordinator.lastLine = line
            let lines = text.components(separatedBy: "\n")
            let offset = lines.prefix(max(0, line - 1)).reduce(0) { $0 + ($1 as NSString).length + 1 }
            let range = NSRange(location: min(offset, (text as NSString).length), length: 0)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var lastLine: Int?
        var lastScrollFraction = 0.0
        var scrollObserver: NSObjectProtocol?
        init(_ parent: MarkdownEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
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
                }
            }
        }
    }
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let observer = coordinator.scrollObserver { NotificationCenter.default.removeObserver(observer) }
    }
}
