@testable import LeonardoDesktopSync
import LeonardoCore
import LeonardoSync
import XCTest

final class DesktopFormCompletionHostTests: XCTestCase {
    func testResourceChangePreventsFinalizationAndForceRevocationIsVisibleToDevice() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let formURL = root.appendingPathComponent("form.mdlf")
        let imageURL = root.appendingPathComponent("image.png")
        let form = LeonardoDocument(body: "![Reference](image.png)\n\n{{field:name}}",
            metadata: LeonardoMetadata(document: LeonardoDocumentDescriptor(kind: .form),
                fields: ["name": LeonardoFieldDefinition(required: true)]))
        let formData = Data(try LeonardoFormatParser.serialize(form).utf8)
        let image = Data([1])
        try formData.write(to: formURL)
        try image.write(to: imageURL)
        let cached = try RemoteFormSource(file: CorpusFile(path: "form.mdlf", content: formData)) {
            CorpusFile(path: $0, content: image)
        }
        let descriptor = SharedProjectDescriptor(id: UUID(), name: "Shared forms", scope: try CorpusScope(folder: ""),
            selection: try CorpusSelection(folders: [], documents: ["form.mdlf", "image.png"]))
        let source = SharedProjectSource(descriptor: descriptor, rootURL: root) {
            CorpusSnapshot(revision: "", files: [])
        }
        let store = LeonardoFormReservationStore(root: root.appendingPathComponent("reservations"))
        let host = DesktopFormCompletionHost(reservations: store, checkEditor: { _ in })
        let session = UUID()
        let device = UUID()

        func command(_ action: RemoteFormCompletionCommand.Action) -> RemoteFormCompletionCommand {
            RemoteFormCompletionCommand(action: action, sessionID: session, path: "form.mdlf",
                revision: cached.revision, values: action == .finish ? ["name": .string("Ana")] : nil)
        }

        XCTAssertEqual(try host.handle(command(.acquire), deviceID: device, source: source).state, .active)
        XCTAssertThrowsError(try host.handle(command(.status), deviceID: UUID(), source: source))
        try Data([2]).write(to: imageURL)
        XCTAssertThrowsError(try host.handle(command(.finish), deviceID: device, source: source)) {
            XCTAssertEqual($0 as? RemoteFormCompletionError, .staleRevision)
        }
        let reservation = try XCTUnwrap(store.activeReservation(for: formURL))
        try store.forceRevoke(reservation, for: formURL)
        XCTAssertEqual(try host.handle(command(.status), deviceID: device, source: source).state, .revoked)
        XCTAssertEqual(try host.handle(command(.finish), deviceID: device, source: source).state, .revoked)
        XCTAssertNil(try store.activeReservation(for: formURL))
    }
}
