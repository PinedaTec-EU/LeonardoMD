import AppKit
import SwiftUI

struct ProjectTreeDragSource: NSViewRepresentable {
    let url: URL
    let session: AppSession
    let isActiveTab: Bool
    let selectedURLs: () -> [URL]
    let onMouseDown: (NSEvent.ModifierFlags, Int) -> Void
    let onMouseUp: (NSEvent.ModifierFlags, Int) -> Void

    func makeNSView(context: Context) -> ProjectTreeDragSourceView {
        let view = ProjectTreeDragSourceView(frame: .zero)
        view.url = url
        view.session = session
        view.isActiveTab = isActiveTab
        view.selectedURLs = selectedURLs
        view.onMouseDown = onMouseDown
        view.onMouseUp = onMouseUp
        return view
    }

    func updateNSView(_ view: ProjectTreeDragSourceView, context: Context) {
        view.url = url
        view.session = session
        view.isActiveTab = isActiveTab
        view.selectedURLs = selectedURLs
        view.onMouseDown = onMouseDown
        view.onMouseUp = onMouseUp
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ProjectTreeDragSourceView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }
}

@MainActor
final class ProjectTreeDragSourceView: NSView, NSDraggingSource {
    var url = URL(fileURLWithPath: "/")
    weak var session: AppSession?
    var isActiveTab = true
    var selectedURLs: () -> [URL] = { [] }
    var onMouseDown: ((NSEvent.ModifierFlags, Int) -> Void)?
    var onMouseUp: ((NSEvent.ModifierFlags, Int) -> Void)?

    private var draggingSession: NSDraggingSession?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { ProjectTreeDragSourceRegistry.shared.unregister(self) }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { ProjectTreeDragSourceRegistry.shared.register(self) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func beginDrag(with event: NSEvent) {
        let urls = selectedURLs()
        guard let primaryURL = urls.first, let session, let root = session.projectURL else { return }
        ProjectTreeDragSourceRegistry.shared.begin(self, root: root, urls: urls)
        let pasteboardItem = DocumentDropProviders.projectTreePasteboardItem(
            for: primaryURL, selecting: urls)
        let item = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let icon = NSWorkspace.shared.icon(forFile: primaryURL.path)
        let preview = dragPreview(icon: icon, count: urls.count)
        let size = preview.size
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                     width: size.width, height: size.height), contents: preview)
        draggingSession = beginDraggingSession(with: [item], event: event, source: self)
        draggingSession?.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func dragPreview(icon: NSImage, count: Int) -> NSImage {
        let iconRect = NSRect(x: 0, y: 0, width: 32, height: 32)
        let badge = NSAttributedString(string: count.formatted(), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.alternateSelectedControlTextColor
        ])
        let badgeSize = badge.size()
        let width = max(18, ceil(badgeSize.width) + 8)
        let size = NSSize(width: count > 1 ? 24 + width : iconRect.width, height: 36)
        return NSImage(size: size, flipped: false) { _ in
            icon.draw(in: iconRect)
            if count > 1 {
                let rect = NSRect(x: 24, y: 18, width: width, height: 18)
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
                badge.draw(at: NSPoint(x: rect.midX - badgeSize.width / 2,
                                       y: rect.midY - badgeSize.height / 2))
            }
            return true
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.copy, .move] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        draggingSession = nil
        ProjectTreeDragSourceRegistry.shared.end(self)
    }
}

@MainActor
final class ProjectTreeDragSourceRegistry {
    static let shared = ProjectTreeDragSourceRegistry()

    private final class WeakView {
        weak var value: ProjectTreeDragSourceView?
        init(_ value: ProjectTreeDragSourceView) { self.value = value }
    }

    private var views: [ObjectIdentifier: WeakView] = [:]
    private var monitor: Any?
    private weak var activeView: ProjectTreeDragSourceView?
    private var dragStartPoint: NSPoint?
    private var dragStartEvent: NSEvent?
    private weak var draggingView: ProjectTreeDragSourceView?
    private var draggedRoot: URL?
    private var draggedURLs: [URL] = []

    func begin(_ view: ProjectTreeDragSourceView, root: URL, urls: [URL]) {
        draggingView = view
        draggedRoot = root
        draggedURLs = urls
    }

    func end(_ view: ProjectTreeDragSourceView) {
        guard draggingView === view else { return }
        draggingView = nil
        draggedRoot = nil
        draggedURLs = []
    }

    func selection(for session: AppSession, destination: URL) -> [URL]? {
        guard draggingView?.session === session, let draggedRoot,
              draggedRoot == session.projectURL else { return nil }
        let target = destination.standardizedFileURL.path
        guard !draggedURLs.contains(where: { url in
            let source = url.standardizedFileURL.path
            return target == source || target.hasPrefix(source + "/")
        }) else { return nil }
        return draggedURLs
    }

    func register(_ view: ProjectTreeDragSourceView) {
        views[ObjectIdentifier(view)] = WeakView(view)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.capture(event)
            return event
        }
    }

    func unregister(_ view: ProjectTreeDragSourceView) {
        end(view)
        views.removeValue(forKey: ObjectIdentifier(view))
        views = views.filter { $0.value.value != nil }
        if activeView === view {
            activeView = nil
            self.dragStartPoint = nil
            dragStartEvent = nil
        }
        guard views.isEmpty, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }

    static func canReceiveMouseEvent(_ view: ProjectTreeDragSourceView, event: NSEvent) -> Bool {
        guard view.isActiveTab, !view.isHiddenOrHasHiddenAncestor,
              let window = view.window, window === event.window,
              window.isVisible, !window.isMiniaturized else { return false }
        return true
    }

    static func canCapture(_ view: ProjectTreeDragSourceView, event: NSEvent) -> Bool {
        guard canReceiveMouseEvent(view, event: event) else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }

    private func capture(_ event: NSEvent) {
        views = views.filter { $0.value.value != nil }
        switch event.type {
        case .leftMouseDown:
            let target = views.values.compactMap(\.value).first { Self.canCapture($0, event: event) }
            activeView = target
            dragStartPoint = target?.convert(event.locationInWindow, from: nil)
            dragStartEvent = target == nil ? nil : event
            target?.onMouseDown?(event.modifierFlags, event.clickCount)
        case .leftMouseDragged:
            guard let target = activeView else { return }
            guard Self.canReceiveMouseEvent(target, event: event),
                  let dragStartPoint, let dragStartEvent else {
                activeView = nil
                self.dragStartPoint = nil
                self.dragStartEvent = nil
                return
            }
            let point = target.convert(event.locationInWindow, from: nil)
            let dx = point.x - dragStartPoint.x
            let dy = point.y - dragStartPoint.y
            guard dx * dx + dy * dy >= 25 else { return }
            activeView = nil
            self.dragStartPoint = nil
            self.dragStartEvent = nil
            target.beginDrag(with: dragStartEvent)
        case .leftMouseUp:
            if let target = activeView, Self.canCapture(target, event: event) {
                target.onMouseUp?(event.modifierFlags, event.clickCount)
            }
            activeView = nil
            dragStartPoint = nil
            dragStartEvent = nil
        default:
            break
        }
    }
}
