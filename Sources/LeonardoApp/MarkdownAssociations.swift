import AppKit
import Observation
import OSLog

@MainActor @Observable
final class MarkdownAssociations {
    static let shared = MarkdownAssociations()
    static let suppressionKey = "suppressMarkdownDefaultPrompt"
    enum Status { case unavailable, unknown, otherApplication, leonardo }
    enum Choice { case useLeonardo, askNextTime, neverAskAgain }

    private(set) var status: Status = .unknown
    private(set) var isChanging = false
    private(set) var isPromptVisible = false
    private(set) var changeFailed = false
    var askAtStartup: Bool {
        didSet { defaults.set(!askAtStartup, forKey: Self.suppressionKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let driver: any MarkdownAssociationDriver
    @ObservationIgnored private var checkedStartup = false
    @ObservationIgnored private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "file-associations")

    init(defaults: UserDefaults = .standard, driver: any MarkdownAssociationDriver = WorkspaceMarkdownAssociationDriver()) {
        self.defaults = defaults
        self.driver = driver
        askAtStartup = !defaults.bool(forKey: Self.suppressionKey)
    }

    func refresh() {
        guard driver.isAvailable else { status = .unavailable; return }
        do { status = try driver.isDefault() ? .leonardo : .otherApplication }
        catch {
            status = .unknown
            logger.error("markdown_association_check_failed")
        }
    }

    /// Called only by the primary process after pending Finder opens are handled.
    func claimStartupPrompt() -> Bool {
        guard !checkedStartup else { return false }
        checkedStartup = true
        refresh()
        guard askAtStartup, status == .otherApplication, !isChanging else { return false }
        isPromptVisible = true
        return true
    }

    func presentStartupPrompt(on window: NSWindow) {
        guard claimStartupPrompt() else { return }
        let alert = Self.startupAlert()
        alert.beginSheetModal(for: window) { [weak self, weak window] response in
            Task { @MainActor in
                let choice: Choice = response == .alertFirstButtonReturn ? .useLeonardo
                    : response == .alertThirdButtonReturn ? .neverAskAgain : .askNextTime
                await self?.choose(choice)
                if self?.changeFailed == true, choice == .useLeonardo,
                   let window, window.isVisible {
                    let failure = NSAlert()
                    failure.messageText = L10n.text("Markdown default was not fully changed")
                    failure.informativeText = L10n.text("The change was cancelled or could not be completed. Check General preferences to see the current association and try again.")
                    await failure.beginSheetModal(for: window)
                }
            }
        }
    }

    static func startupAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = L10n.text("Open Markdown files with LeonardoMD by default?")
        alert.informativeText = L10n.text("This applies to .md and .markdown files on this Mac. Text files (.txt) are unchanged. You can change this in General preferences.")
        alert.addButton(withTitle: L10n.text("Use LeonardoMD"))
        alert.addButton(withTitle: L10n.text("Ask next time")).keyEquivalent = "\u{1b}"
        alert.addButton(withTitle: L10n.text("Never ask again"))
        return alert
    }

    func choose(_ choice: Choice) async {
        isPromptVisible = false
        switch choice {
        case .useLeonardo: await makeDefault()
        case .askNextTime: break
        case .neverAskAgain: askAtStartup = false
        }
    }

    func makeDefault() async {
        guard driver.isAvailable, !isChanging, !isPromptVisible else { return }
        isChanging = true
        changeFailed = false
        defer { isChanging = false }
        do {
            try await driver.makeDefault()
            refresh()
            changeFailed = status != .leonardo
        } catch {
            refresh()
            changeFailed = true
        }
        logger.info("markdown_association_change success=\(!self.changeFailed, privacy: .public)")
    }
}
