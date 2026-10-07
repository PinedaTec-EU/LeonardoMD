import Foundation
import OSLog
import Darwin

/// Emits breadcrumbs before AppKit exists; never includes documents, arguments or environment values.
@MainActor
final class StartupDiagnostics {
    enum Phase: String, Codable {
        case processStarted = "process_started"
        case applicationInitializing = "application_initializing"
        case applicationInitialized = "application_initialized"
        case delegateInstalled = "delegate_installed"
        case activationPolicyRequested = "activation_policy_requested"
        case eventLoopStarting = "event_loop_starting"
        case applicationWillFinishLaunching = "application_will_finish_launching"
        case applicationDidFinishLaunching = "application_did_finish_launching"
        case menuConfiguring = "menu_configuring"
        case menuConfigured = "menu_configured"
        case firstWindowCreating = "first_window_creating"
        case firstWindowCreated = "first_window_created"
        case firstWindowShown = "first_window_shown"
        case applicationReady = "application_ready"
        case applicationWillTerminate = "application_will_terminate"
        case eventLoopReturned = "event_loop_returned"
    }

    struct Context: Codable {
        let pid: Int32
        let parentPID: Int32
        let startedAt: Double
        let bundleIdentifier: String
        let version: String
        let build: String
        let isAppBundle: Bool
        let operatingSystem: String
        let architecture: String

        static var current: Context {
            let bundle = Bundle.main
            #if arch(arm64)
            let architecture = "arm64"
            #elseif arch(x86_64)
            let architecture = "x86_64"
            #else
            let architecture = "other"
            #endif
            return Context(
                pid: getpid(), parentPID: getppid(), startedAt: Date().timeIntervalSince1970,
                bundleIdentifier: bundle.bundleIdentifier ?? "unknown",
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                isAppBundle: bundle.bundleURL.pathExtension == "app",
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                architecture: architecture
            )
        }
    }

    struct ActivationPolicyResult: Codable {
        let switchSucceeded: Bool
        let actualPolicy: Int
    }

    struct Record: Codable {
        let event: String
        let phase: Phase
        let elapsedMilliseconds: Double
        let isMainThread: Bool
        let context: Context
        let activationPolicy: ActivationPolicyResult?
    }

    private let context: Context
    private let started = ContinuousClock.now
    private let writeToStandardError: (Data) throws -> Void
    // Initialize the unified logger only after the first synchronous stderr breadcrumb.
    private lazy var logger = Logger(subsystem: "eu.pinedatec.LeonardoMD", category: "startup")

    init(context: Context = .current, writeToStandardError: @escaping (Data) throws -> Void = {
        try FileHandle.standardError.write(contentsOf: $0)
    }) {
        self.context = context
        self.writeToStandardError = writeToStandardError
    }

    func record(_ phase: Phase, activationPolicy: ActivationPolicyResult? = nil) {
        let elapsed = started.duration(to: .now).components
        let record = Record(
            event: "application_startup", phase: phase,
            elapsedMilliseconds: Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
            isMainThread: Thread.isMainThread, context: context, activationPolicy: activationPolicy
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(record) else { return }
        // No buffering: a SIGABRT in the next framework call must leave the preceding phase intact.
        try? writeToStandardError(data + Data([0x0A]))
        let message = String(decoding: data, as: UTF8.self)
        logger.notice("\(message, privacy: .public)")
    }
}
