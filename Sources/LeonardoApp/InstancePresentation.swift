import AppKit
import Observation
import OSLog

/// Presentation ownership is independent from synchronization ownership. All
/// cooperating processes elect the oldest live peer, including QA bundle copies.
@MainActor @Observable
final class InstancePresentation: NSObject {
    static let shared = InstancePresentation()
    private(set) var peers: [UpdateProcessIdentity] = []
    private(set) var allowsMultipleInstances = false
    private var refreshTask: Task<Void, Never>?
    private var observedPreferences: [Bool] = []
    private let logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "instance-presentation")

    static func representative(in peers: [UpdateProcessIdentity]) -> UpdateProcessIdentity? {
        peers.min {
            $0.launchDate == $1.launchDate ? $0.pid < $1.pid : $0.launchDate < $1.launchDate
        }
    }

    static func activationPolicy(grouped: Bool, current: UpdateProcessIdentity,
                                 peers: [UpdateProcessIdentity]) -> NSApplication.ActivationPolicy {
        grouped && representative(in: peers) != current && peers.contains(current) ? .accessory : .regular
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        peers = []
    }

    private func refresh() async {
        let preferences = InstancePreferences.shared
        let values = [preferences.allowsMultipleInstances, preferences.groupsInstances]
        if observedPreferences != values {
            observedPreferences = values
            preferences.refreshObservation()
        }
        allowsMultipleInstances = values[0]
        guard let current = try? UpdateProcessIdentity.identify(.current) else { return }
        var found = [current]
        for app in NSWorkspace.shared.runningApplications {
            guard !Task.isCancelled else { return }
            guard !app.isTerminated, app.processIdentifier != current.pid,
                  app.executableURL?.lastPathComponent == "LeonardoMD",
                  let identity = try? UpdateProcessIdentity.identify(app),
                  await UpdateQuitEndpoint.send(.presentation, identity: identity) != nil,
                  isRunning(identity) else { continue }
            found.append(identity)
        }
        guard !Task.isCancelled else { return }
        found.sort { $0.launchDate == $1.launchDate ? $0.pid < $1.pid : $0.launchDate < $1.launchDate }
        if peers != found { peers = found }
        var policy = Self.activationPolicy(grouped: preferences.groupingEnabled, current: current, peers: found)
        // Never hide behind a missing/hidden representative. The elected process
        // first becomes regular; followers converge on the next refresh.
        if policy == .accessory,
           let leader = Self.representative(in: found),
           NSRunningApplication(processIdentifier: leader.pid)?.activationPolicy != .regular {
            policy = .regular
        }
        guard NSApp.activationPolicy() != policy else { return }
        let success = NSApp.setActivationPolicy(policy)
        logger.info("instance_presentation_changed pid=\(current.pid) policy=\(policy.rawValue) success=\(success)")
    }

    private func isRunning(_ identity: UpdateProcessIdentity) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: identity.pid), !app.isTerminated else { return false }
        return (try? UpdateProcessIdentity.identify(app)) == identity
    }

    func activate(_ identity: UpdateProcessIdentity) {
        guard isRunning(identity) else { return }
        Task { _ = await UpdateQuitEndpoint.send(.activate, identity: identity) }
    }

    func label(for identity: UpdateProcessIdentity) -> String {
        let current = identity.pid == ProcessInfo.processInfo.processIdentifier
        return L10n.text("Instance") + " \(identity.pid)" + (current ? " · " + L10n.text("Current") : "")
    }

    func dockMenu() -> NSMenu? {
        guard allowsMultipleInstances else { return nil }
        let menu = NSMenu(title: L10n.text("Instances"))
        for identity in peers where isRunning(identity) {
            let item = NSMenuItem(title: label(for: identity), action: #selector(selectInstance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = identity
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectInstance(_ item: NSMenuItem) {
        guard let identity = item.representedObject as? UpdateProcessIdentity else { return }
        activate(identity)
    }
}
