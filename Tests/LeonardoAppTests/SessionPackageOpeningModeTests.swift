import XCTest
import Foundation
import LeonardoCore
@testable import LeonardoApp

@MainActor
final class SessionPackageOpeningModeTests: XCTestCase {
    func testMDLFPackageUsesNormalOpeningPreference() async throws {
        for preference in MarkdownMode.allCases {
            for extracted in [false, true] {
                try await verifyOpening(response: false, preference: preference, extracted: extracted,
                                        expected: DocumentMode(rawValue: preference.rawValue)!)
            }
        }
    }

    func testMDLRPackageKeepsFillModeRegardlessOfOpeningPreference() async throws {
        for preference in MarkdownMode.allCases {
            for extracted in [false, true] {
                try await verifyOpening(response: true, preference: preference, extracted: extracted, expected: .fill)
            }
        }
    }

    private func verifyOpening(response: Bool, preference: MarkdownMode, extracted: Bool,
                               expected: DocumentMode) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tabs = DocumentTabs(preferencesURL: root.appendingPathComponent("preferences.json"))
        defer { tabs.stop(); try? FileManager.default.removeItem(at: root) }
        let documentURL = root.appendingPathComponent(response ? "request.mdlr" : "request.mdlf")
        let packageURL = root.appendingPathComponent("request.mdlz")
        let source = try LeonardoFormatParser.serialize(LeonardoDocument(
            body: "# Request\n\nName: {{field:name}}",
            metadata: LeonardoMetadata(document: LeonardoDocumentDescriptor(kind: .form),
                                       fields: ["name": LeonardoFieldDefinition(required: true)])
        ))
        try source.write(to: documentURL, atomically: true, encoding: .utf8)
        try LeonardoPackageTransport.export(documentURL: documentURL, content: source, to: packageURL)
        let before = try Data(contentsOf: packageURL)
        let session = tabs.activeSession
        session.authorizePath = { _, _ in }
        session.globalPreferences.markdown.defaultMode = preference
        session.mode = .edit
        let opened = await session.openLeonardoPackage(packageURL,
            extractingTo: extracted ? root.appendingPathComponent("extracted", isDirectory: true) : nil)
        XCTAssertTrue(opened)
        XCTAssertEqual(session.mode, expected, "response=\(response), preference=\(preference), extracted=\(extracted)")
        XCTAssertEqual(session.documentStorage, extracted ? .extracted : .package)
        XCTAssertEqual(session.documentSourceURL, packageURL)
        XCTAssertTrue(session.isProtected)
        XCTAssertEqual(session.content, source)
        XCTAssertEqual(try Data(contentsOf: packageURL), before)
        session.discardPackageWorkspace()
        await session.waitForPackageWorkspaceDisposal()
    }
}
