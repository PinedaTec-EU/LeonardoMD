import AppKit
import SwiftUI
import XCTest
import LeonardoCore
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
                state: "Production object inspector; isolated inserted synthetic rubric; no personal ink; editable geometry, Z and color")
            session.stop()
        }
    }
}
