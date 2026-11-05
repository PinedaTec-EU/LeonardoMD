import AppKit
import SwiftUI
import XCTest
import LeonardoCore
import LeonardoSync
import LeonardoDesktopSync
@testable import LeonardoApp

@MainActor
final class RubricGuideCaptureTests: XCTestCase {
    func testCaptureRubricEditorAndHeader() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_RUBRIC_GUIDE_CAPTURE"] else { throw XCTSkip("Opt-in help illustration") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let ink = LeonardoRubric(strokes: [.init(color: "#194D80", width: 5, style: .brush,
            points: [.init(x: 40, y: 140), .init(x: 100, y: 40), .init(x: 80, y: 150), .init(x: 200, y: 90), .init(x: 300, y: 120), .init(x: 560, y: 70)])])
        let old = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = old }
        for language in AppLanguage.allCases {
            LanguageSettings.shared.language = language
            let code = language.rawValue
            let library = RubricLibrary(url: root.appendingPathComponent("library-" + code + ".json"))
            let folder = URL(fileURLWithPath: path).appendingPathComponent(code)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if library.entries.isEmpty { try library.add(label: code == "es" ? "Rúbrica de ejemplo" : "Example rubric", rubric: ink) }
            let session = AppSession(preferencesURL: root.appendingPathComponent("prefs.json"))
            session.rubricLibrary = library
            session.documentURL = root.appendingPathComponent("Inspection.mdlf")
            session.documentKind = .leonardoTemplate
            session.isProtected = false
            session.content = try LeonardoFormatParser.serialize(.init(body: "# Synthetic inspection"))
            let request = RubricRequest(documentURL: session.documentURL, source: session.content, fieldID: nil)
            let editor = NSHostingView(rootView: RubricEditor(request: request, library: library) { _, _, _ in false }
                .modifier(SessionAppearance(session: session)).frame(width: 696, height: 580).background(Color(nsColor: .windowBackgroundColor)))
            try await GuideCaptureSupport.captureNative(editor, size: NSSize(width: 696, height: 580),
                to: folder.appendingPathComponent("rubric-canvas.png"), language: code,
                state: "Production rubric editor; isolated synthetic library; empty new canvas; no device or legal signing")
            let controller = DesktopSyncController(preferencesURL: root.appendingPathComponent("capture-prefs-\(code).json"))
            let linkedEditor = NSHostingView(rootView: RubricEditor(request: request, library: library,
                syncController: controller) { _, _, _ in false }
                .modifier(SessionAppearance(session: session)).frame(width: 696, height: 360).background(Color(nsColor: .windowBackgroundColor)))
            try await GuideCaptureSupport.captureNative(linkedEditor, size: NSSize(width: 696, height: 360),
                to: folder.appendingPathComponent("rubric-linked-offline.png"), language: code,
                state: "Production linked-rubric section; helper offline state; isolated synthetic data; no device or legal signing",
                pixelScale: 0.72)
            try await captureRequestAndReviewStates(root: root, folder: folder, language: code,
                request: request, library: library, ink: ink)
            let header = NSHostingView(rootView: DocumentToolbar(session: session).modifier(SessionAppearance(session: session)).frame(width: 1260, height: 74).background(Color(nsColor: .windowBackgroundColor)))
            try await GuideCaptureSupport.captureNative(header, size: NSSize(width: 1260, height: 74),
                to: folder.appendingPathComponent("document-toolbar.png"), language: code,
                state: "Production document toolbar; dropdown mode and grouped menus; synthetic document")
            let graphic = LeonardoGraphic(label: code == "es" ? "Rúbrica de ejemplo" : "Example rubric", rubric: ink,
                                          x: 72, y: 688, width: 236, height: 236 / 3, z: 1)
            session.content = try LeonardoFormatParser.serialize(.init(body: "# Synthetic inspection", metadata: .init(layout: .init(objects: [graphic]))))
            session.receiveGraphicSelection(expected: session.content, id: graphic.id, inspect: true)
            let inspector = NSHostingView(rootView: GraphicInspector(session: session, graphic: graphic)
                .modifier(SessionAppearance(session: session)).frame(width: 320, height: 850).background(Color(nsColor: .windowBackgroundColor)))
            try await GuideCaptureSupport.captureNative(inspector, size: NSSize(width: 320, height: 850),
                to: folder.appendingPathComponent("graphic-inspector.png"), language: code,
                state: "Production object inspector; isolated inserted synthetic rubric; no personal ink; editable geometry, Z and color; original 1x bitmap for guide memory budget", pixelScale: 1)
            session.stop()
        }
    }

    private func captureRequestAndReviewStates(root: URL, folder: URL, language: String,
                                               request: LeonardoApp.RubricRequest, library: RubricLibrary,
                                               ink: LeonardoRubric) async throws {
        let targetID = UUID()
        let ownerID = UUID()
        let now = Date()
        var pending = try LeonardoSync.RubricRequest(id: UUID(), targetDeviceID: targetID,
            requesterID: ownerID, requesterName: "Mac Studio", labelHint: "Geometry",
            createdAt: now)
        let document = root.appendingPathComponent("Inspection.mdlf")
        let source = "# Synthetic inspection"
        let requestStoreURL = root.appendingPathComponent("request-state/MobileSync/RubricCaptures/captures.json")
        let requestStore = RubricCaptureStore(url: requestStoreURL, now: Date.init)
        try requestStore.upsert(RubricCaptureRecord(id: pending.id, targetDeviceID: targetID,
            targetDeviceName: "Little Leonardo", documentURL: document,
            sourceDigest: RubricCaptureRecord.digest(source: source), fieldID: nil,
            labelHint: pending.labelHint, request: pending, updatedAt: now))
        let pendingController = DesktopSyncController(
            preferencesURL: root.appendingPathComponent("request-state/preferences.json"),
            runtime: RubricGuideCaptureRuntime(status: RubricExchangeStatus(request: pending)))
        let pendingEditor = NSHostingView(rootView: RubricEditor(
            request: RubricRequest(documentURL: document, source: source, fieldID: nil), library: library,
            syncController: pendingController) { _, _, _ in false }
            .frame(width: 696, height: 760).background(Color(nsColor: .windowBackgroundColor)))
        try await GuideCaptureSupport.captureNative(pendingEditor, size: NSSize(width: 696, height: 760),
            to: folder.appendingPathComponent("rubric-linked-request.png"), language: language,
            state: "Production linked-rubric request; target Little Leonardo; pending request; synthetic data; no device or legal signing")

        let reviewRoot = root.appendingPathComponent("review-state")
        let reviewStore = RubricCaptureStore(url: reviewRoot.appendingPathComponent("MobileSync/RubricCaptures/captures.json"), now: Date.init)
        pending.state = .completed
        let response = try LeonardoSync.RubricResponse(requestID: pending.id, targetDeviceID: targetID,
            requesterID: ownerID, label: language == "es" ? "Rúbrica revisada" : "Reviewed rubric",
            rubric: ink, submittedAt: now.addingTimeInterval(1))
        try reviewStore.upsert(RubricCaptureRecord(id: pending.id, targetDeviceID: targetID,
            targetDeviceName: "Little Leonardo", documentURL: document,
            sourceDigest: RubricCaptureRecord.digest(source: source), fieldID: nil,
            labelHint: pending.labelHint, request: pending, response: response, updatedAt: now.addingTimeInterval(1)))
        let reviewController = DesktopSyncController(
            preferencesURL: reviewRoot.appendingPathComponent("preferences.json"),
            runtime: RubricGuideCaptureRuntime(status: RubricExchangeStatus(request: pending, response: response)))
        let reviewEditor = NSHostingView(rootView: RubricEditor(
            request: RubricRequest(documentURL: document, source: source, fieldID: nil), library: library,
            syncController: reviewController) { _, _, _ in false }
            .frame(width: 696, height: 760).background(Color(nsColor: .windowBackgroundColor)))
        try await GuideCaptureSupport.captureNative(reviewEditor, size: NSSize(width: 696, height: 760),
            to: folder.appendingPathComponent("rubric-linked-review.png"), language: language,
            state: "Production linked-rubric response review; target Little Leonardo; unsaved response with save actions; synthetic data; no device or legal signing")
    }
}

private actor RubricGuideCaptureRuntime: DesktopSyncRuntimeAccess {
    let registry: PairingRegistry
    let status: RubricExchangeStatus

    init(status: RubricExchangeStatus) {
        self.status = status
        var registry = PairingRegistry()
        registry.setEnabled(true)
        if let credential = try? PairingRegistry.makeCredential(),
           let pairing = try? registry.requestPairing(deviceName: "Little Leonardo", credential: credential,
               serverFingerprint: Data(repeating: 0, count: 32), now: Date(), kind: .readOnly,
               capabilities: [.rubricExchangeV1]) {
            _ = try? registry.approve(requestID: pairing.id, comparisonCode: pairing.comparisonCode,
                                      projects: [UUID()], now: Date())
        }
        self.registry = registry
    }

    func start(host: String, port: UInt16, projects: [SharedProjectSource], allowPrivateOverlay: Bool) async throws -> RunningDirectService {
        throw DesktopRuntimeError.notRunning
    }
    func stop() async throws { }
    func consentState() async throws -> PairingRegistry { registry }
    func incomingProposals() async throws -> [DesktopPeerIncomingProposal] { [] }
    func reviewIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload) async throws -> DesktopPeerProposalReview {
        throw DesktopRuntimeError.notRunning
    }
    func applyIncomingProposal(deviceID: UUID, upload: DesktopPeerUpload, review: DesktopPeerProposalReview,
                               decisions: [String: ReconciliationChoice], projectRoot: URL,
                               currentSource: CorpusSnapshot, currentDisk: CorpusSnapshot) async throws -> DesktopPeerAcceptanceResult {
        throw DesktopRuntimeError.notRunning
    }
    func createInvitation() async throws -> PairingInvitation { throw DesktopRuntimeError.notRunning }
    func approve(requestID: UUID, code: String, projectIDs: Set<UUID>) async throws { throw DesktopRuntimeError.notRunning }
    func reject(requestID: UUID) async throws { throw DesktopRuntimeError.notRunning }
    func revoke(deviceID: UUID) async throws { throw DesktopRuntimeError.notRunning }
    func createRubricRequest(deviceID: UUID, requestID: UUID, requesterName: String, labelHint: String?) async throws -> LeonardoSync.RubricRequest {
        status.request
    }
    func cancelRubricRequest(requestID: UUID) async throws -> LeonardoSync.RubricRequest { status.request }
    func rubricResponse(requestID: UUID) async throws -> RubricResponse? { status.response }
    func rubricStatus(requestID: UUID) async throws -> RubricExchangeStatus { status }
}
