import AppKit
import SwiftUI
import WebKit
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
        let language = ProcessInfo.processInfo.environment["LEONARDO_NATIVE_CAPTURE_LANGUAGE"]
            .flatMap(AppLanguage.init(rawValue:)) ?? .spanish
        LanguageSettings.shared.language = language
        let spanish = language == .spanish
        let title = spanish ? "Acuerdo de ejemplo" : "Sample agreement"
        let holder = spanish ? "Titular" : "Holder"
        let witness = spanish ? "Testigo" : "Witness"

        let document = LeonardoDocument(
            body: "# \(title)\n\n## \(holder)\n{{field:holder}}\n\n## \(witness)\n{{field:witness}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "mac-guided-signing-capture", title: title, kind: .form,
                    revision: 1, signing: LeonardoSigningDeclaration(positions: [
                        .init(id: "holder", label: holder), .init(id: "witness", label: witness)
                    ])
                ),
                fields: [
                    "holder": .init(type: .rubric, label: spanish ? "Rúbrica del titular" : "Holder rubric", signerPosition: "holder"),
                    "witness": .init(type: .rubric, label: spanish ? "Rúbrica del testigo" : "Witness rubric", signerPosition: "witness")
                ]
            )
        )
        let session = AppSession(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { session.stop() }
        await session.initialize()
        session.globalPreferences.palette = .leonardoClassic
        let documentURL = root.appendingPathComponent(title + ".mdlf")
        let source = try LeonardoFormatParser.serialize(document)
        try source.write(to: documentURL, atomically: true, encoding: .utf8)
        session.documentURL = documentURL
        session.documentKind = .leonardoTemplate
        session.content = source
        session.snapshot = try await session.documents.read(documentURL)
        session.guidedSigningSession = try LeonardoGuidedSigningSession(document: document, at: Date())
        session.guidedSigningTrustStore = try LeonardoSigningTrustRegistry(credentials: [])
        session.guidedSigningReady = true
        XCTAssertTrue(session.guidedSigningWorkflowOperable)
        try await capture(WorkspaceView(session: session), name: "mac-al-abrir",
                          size: NSSize(width: 1260, height: 740), session: session, folder: folder)
        session.mode = .fill
        session.showInspector = true

        try await capture(WorkspaceView(session: session), name: "mac-documento-con-firmas",
                          size: NSSize(width: 1260, height: 740), session: session, folder: folder)
        try await captureRenderedDocument(title: title, session: session, folder: folder)

        try await capture(DocumentToolbar(session: session), name: "mac-barra-documento",
                          size: NSSize(width: 1260, height: 72), session: session, folder: folder)
        try await capture(GuidedSigningView(session: session), name: "mac-firma-pendiente",
                          size: NSSize(width: 390, height: 660), session: session, folder: folder)
        try await capture(GuidedSigningRubricCapture(title: spanish ? "Rúbrica del titular" : "Holder rubric", initialRubric: nil) { _ in },
                          name: "mac-lienzo-rubrica", size: NSSize(width: 660, height: 445),
                          session: session, folder: folder)
        try await capture(GuidedSigningLinkedRubricPanel(title: spanish ? "Rúbrica del titular" : "Holder rubric", drawLocally: {}, close: {}) {
            GuidedSigningRubricWaitingView(deviceName: spanish ? "Little Leonardo de prueba" : "Test Little Leonardo", cancel: {})
        }, name: "mac-espera-rubrica-enlazada", size: NSSize(width: 460, height: 380),
           session: session, folder: folder)
        try await captureMixedVerification(document: document, session: session, folder: folder)
    }

    private func captureMixedVerification(document: LeonardoDocument, session: AppSession, folder: URL) async throws {
        var document = document
        let spanish = LanguageSettings.shared.language == .spanish
        let reviewer = spanish ? "Revisor" : "Reviewer"
        document.body += "\n\n## \(reviewer)\n{{field:reviewer}}"
        var positions = try XCTUnwrap(document.metadata.document.signing?.positions)
        positions.append(.init(id: "reviewer", label: reviewer))
        document.metadata.document.signing = .init(positions: positions)
        document.metadata.fields["reviewer"] = .init(
            type: .rubric, label: spanish ? "Rúbrica del revisor" : "Reviewer rubric", signerPosition: "reviewer"
        )
        let keys = positions.map { LeonardoSigningKeyPair(credentialID: "capture-" + $0.id) }
        let initialTrust = try LeonardoSigningTrustRegistry(credentials: keys.map(\.credential))
        var signed = try LeonardoGuidedSigningSession(document: document, at: Date())
        for (position, key) in zip(positions, keys) {
            let profile = LeonardoSignerProfile(displayName: position.label, identity: .init(
                fullName: position.label, documentType: .nationalID, documentNumber: "QA-" + position.id
            ))
            let authorization = try LeonardoSigningAuthorization(positionID: position.id, profileID: profile.id,
                credentialID: key.credential.id, confirmedAt: Date(), explicitlyConfirmed: true)
            try signed.assign(positionID: position.id, profile: profile, credential: key.credential,
                              authorization: authorization, at: Date())
        }
        let rubric = LeonardoRubric(strokes: [.init(color: "#111111", width: 2, style: .solid,
            points: [.init(x: 1, y: 1), .init(x: 2, y: 2)])])
        for (position, key) in zip(positions, keys) {
            _ = try signed.begin(positionID: position.id, document: document)
            try signed.confirmLocation(positionID: position.id, fieldID: position.id, occurrence: 0,
                document: document, contextRead: true, rubric: rubric, at: Date())
            _ = try signed.sign(positionID: position.id, keyPair: key, document: document,
                                trustStore: initialTrust, at: Date())
        }
        let otherKey = LeonardoSigningKeyPair(credentialID: keys[2].credential.id)
        let reducedTrust = try LeonardoSigningTrustRegistry(credentials: [keys[0].credential, otherKey.credential])
        session.content = try LeonardoFormatParser.serialize(document)
        session.guidedSigningSession = signed
        session.guidedSigningTrustStore = reducedTrust
        session.guidedSigningVerification = signed.signatureVerification(document: document, trustStore: reducedTrust)
        XCTAssertEqual(session.guidedSigningVerification, [
            "holder": .valid, "witness": .unknownCredential(keys[1].credential.id), "reviewer": .invalidSignature
        ])
        try await capture(GuidedSigningView(session: session), name: "mac-verificacion-por-firmante",
                          size: NSSize(width: 460, height: 690), session: session, folder: folder)
        try await capture(GuidedSigningView(session: session), name: "mac-guia-verificacion",
                          size: NSSize(width: 370, height: 275), session: session, folder: folder, pixelScale: 1)
    }

    private func captureRenderedDocument(title: String, session: AppSession, folder: URL) async throws {
        let hosting = NSHostingView(rootView: WorkspaceView(session: session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1260, height: 740),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }

        func findWebView(_ node: NSView) -> WKWebView? {
            if let web = node as? WKWebView { return web }
            return node.subviews.lazy.compactMap(findWebView).first
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        repeat {
            if let web = findWebView(hosting), session.renderer.isReady,
               (try? await web.evaluateJavaScript("""
                   document.querySelector('h1')?.textContent === '\(title)' &&
                   window.LeonardoForms?.hasFieldTarget('holder', 0) === true
                   """)) as? Bool == true {
                try await GuideCaptureSupport.capture(
                    web, to: folder.appendingPathComponent("mac-formulario-renderizado.png"),
                    language: LanguageSettings.shared.language.rawValue, state: "Rendered guided signing form in the native Mac document viewport",
                    route: "/native/firmas/mac-formulario-renderizado", screen: "mac-formulario-renderizado"
                )
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        XCTFail("Native guided signing preview did not display the form and first signature occurrence")
    }

    private func capture<Content: View>(_ content: Content, name: String, size: NSSize,
                                        session: AppSession, folder: URL, pixelScale: CGFloat? = nil) async throws {
        let host = NSHostingView(rootView: content
            .modifier(SessionAppearance(session: session))
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor)))
        let imageURL = folder.appendingPathComponent(name + ".png")
        try await GuideCaptureSupport.captureNative(host, size: size,
            to: imageURL, language: LanguageSettings.shared.language.rawValue,
            state: "macOS production component with an isolated synthetic signing form", pixelScale: pixelScale,
            route: "/native/firmas/" + name, screen: name)
        let contextURL = imageURL.deletingPathExtension().appendingPathExtension("context.json")
        let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: imageURL)))
        var context = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: contextURL)) as? [String: Any])
        context["image_pixels"] = ["width": image.pixelsWide, "height": image.pixelsHigh]
        try JSONSerialization.data(withJSONObject: context, options: [.prettyPrinted, .sortedKeys])
            .write(to: contextURL)
    }
}
