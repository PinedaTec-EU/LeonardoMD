import AppKit
import SwiftUI
import XCTest
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class GuidedSigningCaptureTests: XCTestCase {
    func testCaptureMacSigningComponents() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEONARDO_GUIDED_SIGNING_CAPTURE"] else {
            throw XCTSkip("Opt-in guided signing illustration")
        }
        let folder = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let previousLanguage = LanguageSettings.shared.language
        defer { LanguageSettings.shared.language = previousLanguage }
        LanguageSettings.shared.language = .spanish

        let document = LeonardoDocument(
            body: "# Acuerdo de ejemplo\n\n## Titular\n{{field:holder}}\n\n## Testigo\n{{field:witness}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "mac-guided-signing-capture", title: "Acuerdo de ejemplo", kind: .form,
                    revision: 1, signing: LeonardoSigningDeclaration(positions: [
                        .init(id: "holder", label: "Titular"), .init(id: "witness", label: "Testigo")
                    ])
                ),
                fields: [
                    "holder": .init(type: .rubric, label: "Rúbrica del titular", signerPosition: "holder"),
                    "witness": .init(type: .rubric, label: "Rúbrica del testigo", signerPosition: "witness")
                ]
            )
        )
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.initialize()
        session.globalPreferences.palette = .leonardoClassic
        session.documentURL = root.appendingPathComponent("Acuerdo de ejemplo.mdlf")
        session.documentKind = .leonardoTemplate
        session.content = try LeonardoFormatParser.serialize(document)
        session.guidedSigningSession = try LeonardoGuidedSigningSession(document: document, at: Date())
        session.guidedSigningTrustStore = try LeonardoSigningTrustRegistry(credentials: [])
        session.guidedSigningReady = true
        XCTAssertTrue(session.guidedSigningWorkflowOperable)
        session.mode = .fill
        session.showInspector = true

        try await capture(WorkspaceView(session: session), name: "mac-documento-con-firmas",
                          size: NSSize(width: 1260, height: 740), session: session, folder: folder)

        try await capture(DocumentToolbar(session: session), name: "mac-barra-documento",
                          size: NSSize(width: 1260, height: 72), session: session, folder: folder)
        try await capture(GuidedSigningView(session: session), name: "mac-firma-pendiente",
                          size: NSSize(width: 390, height: 660), session: session, folder: folder)
        try await capture(GuidedSigningRubricCapture(title: "Rúbrica del titular", initialRubric: nil) { _ in },
                          name: "mac-lienzo-rubrica", size: NSSize(width: 660, height: 445),
                          session: session, folder: folder)
    }

    private func capture<Content: View>(_ content: Content, name: String, size: NSSize,
                                        session: AppSession, folder: URL) async throws {
        let host = NSHostingView(rootView: content
            .modifier(SessionAppearance(session: session))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)))
        try await GuideCaptureSupport.captureNative(host, size: size,
            to: folder.appendingPathComponent(name + ".png"), language: "es",
            state: "macOS production component with an isolated synthetic signing form")
    }
}
