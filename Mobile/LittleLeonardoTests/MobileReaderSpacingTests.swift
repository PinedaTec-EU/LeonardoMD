import SwiftUI
import WebKit
import XCTest
import LeonardoCore
import LeonardoRender
import LeonardoSync
import LeonardoSyncUI
@testable import LittleLeonardo

@MainActor
final class MobileReaderSpacingTests: XCTestCase {
    func testEnrollmentSelectionUsesReturnedCredentialWhenAnotherKeySortsAfterIt() {
        let enrolled = LeonardoSigningCredential(id: "signing-m", publicKey: Data(repeating: 1, count: 32))
        let available = ["signing-a", enrolled.id, "signing-z"]

        XCTAssertEqual(
            MobileGuidedSigningView.selectedCredentialID(
                afterEnrollment: enrolled,
                availableIDs: available
            ),
            enrolled.id
        )
    }

    func testLeonardoDocumentsRenderReadOnlyInLittleLeonardo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let corpus = root.appendingPathComponent("Corpus")
        let projectID = UUID()
        let note = CorpusFile(path: "note.mdlf", content: Data("""
        ---
        {"format":"mdlf","formatVersion":1,"document":{"kind":"document","title":"Portable note"}}
        ---
        # Portable note

        MDLF content stays readable.
        """.utf8))
        let response = CorpusFile(path: "response.mdlr", content: Data("""
        ---
        {"format":"mdlf","formatVersion":1,"document":{"kind":"form","title":"Filled response"},"fields":{"name":{"type":"text","label":"Name"}},"values":{"name":"Ada Lovelace"}}
        ---
        # Filled response

        Name: {{field:name}}
        """.utf8))
        let files = [note, response]
        let project = try OfflineProject(id: projectID, name: "Format reader QA", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "format-reader", files: files))
        try await OfflineCorpusStore(root: corpus).save(project)
        let connection = MobileDirectConnection(deviceID: UUID(), endpoint: URL(string: "https://127.0.0.1:40882")!,
            fingerprint: Data(repeating: 7, count: 32), projectIDs: [projectID], comparisonCode: nil, capabilities: [])
        try MobileDirectConnectionStore(url: root.appendingPathComponent("connections.json")).save([connection])
        let library = MobileLibrary(rootURL: corpus, credentials: ReaderSpacingCredentials())
        await library.reload()
        XCTAssertEqual(library.projects.count, 1)

        for (file, expectedHeading, expectedValue) in [
            (note, "Portable note", nil as String?),
            (response, "Filled response", "Ada Lovelace")
        ] {
            try await assertReadOnlyMobilePreview(library: library, projectID: projectID, file: file,
                                                  expectedHeading: expectedHeading, expectedValue: expectedValue)
        }
    }

    func testGuidedSigningCopyRendersNestedProjectResourcesUsingSourceReferences() async throws {
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let document = LeonardoDocument(
            body: "# Mobile signing practice\n\n![Seal](assets/seal.png)\n\n{{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "mobile-reader-preview", title: "Mobile signing practice", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(
                        type: .rubric, label: "Signature", signerPosition: "owner"
                    )
                ]
            )
        )
        let session = try LeonardoGuidedSigningSession(
            document: document, at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let source = try LeonardoFormatParser.serialize(document)
        let scope = try CorpusScope(folder: "forms")
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let png = try XCTUnwrap(bitmap.pngData())
        let file = CorpusFile(path: "forms/assets/seal.png", content: png)
        let resources = try MobileDocumentView.signingResources(
            source: source, documentPath: "forms/agreement.mdlf", scope: scope, files: [file]
        )
        XCTAssertEqual(resources.map(\.reference), ["assets/seal.png"])
        XCTAssertThrowsError(try MobileDocumentView.signingResources(
            source: source, documentPath: "forms/agreement.mdlf", scope: scope, files: []
        ))
        let exchange = try LeonardoSigningExchange(
            document: document, resources: resources, session: session, trustedCredentials: [], at: Date()
        )
        try exchange.validate(
            against: document,
            resources: [LeonardoSigningResource(reference: "assets/seal.png", bytes: png)],
            trustStore: try LeonardoSigningTrustRegistry(credentials: [])
        )
        let exchangedResources = try exchange.signingResources()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        var available = Set<String>()
        let binding = Binding<Set<String>>(
            get: { available },
            set: { available = $0 }
        )
        func showReader(resources: [LeonardoSigningResource], targetKeys: Binding<Set<String>>) {
            window.rootViewController = UIHostingController(rootView: NavigationStack {
                MobileGuidedSigningDocumentReader(
                    document: document,
                    resources: resources,
                    session: session,
                    trustedCredentials: [],
                    trustAccepted: true,
                    focusTarget: nil,
                    availableTargetKeys: targetKeys,
                    onFocusConsumed: {}
                )
            })
            window.makeKeyAndVisible()
        }
        showReader(resources: exchangedResources, targetKeys: binding)

        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        var evidence = ""
        repeat {
            if let web = findWebView(window),
               let value = try? await web.evaluateJavaScript("""
                    JSON.stringify([
                      document.querySelector('h1')?.textContent,
                      document.querySelector('img[alt=Seal]')?.naturalWidth > 0
                    ])
                    """) as? String {
                evidence = value
                if evidence == "[\"Mobile signing practice\",true]", available.contains("signature#0") {
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        XCTAssertEqual(evidence, "[\"Mobile signing practice\",true]")
        XCTAssertTrue(available.contains("signature#0"))

        var availableWithBrokenImage = Set<String>()
        var everAvailableWithBrokenImage = Set<String>()
        let brokenTargets = Binding<Set<String>>(
            get: { availableWithBrokenImage },
            set: {
                availableWithBrokenImage = $0
                everAvailableWithBrokenImage.formUnion($0)
            }
        )
        showReader(resources: [LeonardoSigningResource(reference: "assets/seal.png", bytes: Data([1, 2, 3]))],
                   targetKeys: brokenTargets)
        let brokenDeadline = ContinuousClock.now.advanced(by: .seconds(12))
        var renderedWithBrokenImage = false
        repeat {
            if let web = findWebView(window),
               let rendered = try? await web.evaluateJavaScript("""
                    (() => {
                      const seal = document.querySelector('img[alt=Seal]');
                      return document.querySelector('.leonardo-guided-signing-field') !== null &&
                        seal !== null && seal.complete && seal.naturalWidth === 0;
                    })()
                    """) as? Bool, rendered {
                renderedWithBrokenImage = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < brokenDeadline
        XCTAssertTrue(renderedWithBrokenImage, "WebKit must reach the exact field while its referenced asset fails to decode")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertTrue(everAvailableWithBrokenImage.isEmpty,
                      "The WebKit handoff must not enable any signature target with a broken image")
    }

    func testNativeSigningFallbackRequiresFullReaderForOrdinaryInk() throws {
        let exchange = try makeSignedGuidedSigningExchange()
        var document = try exchange.document()
        XCTAssertFalse(MobileGuidedSigningNativeContent.requiresFullReader(document))
        let ink = try XCTUnwrap(exchange.session.positions.values.first?.locations.first?.rubric)
        let authored = try JSONDecoder().decode(LeonardoJSONValue.self, from: JSONEncoder().encode(ink))

        document.body += "\n\n{{field:ordinary}}"
        document.metadata.fields["ordinary"] = .init(type: .rubric, required: true, defaultValue: authored)
        XCTAssertTrue(MobileGuidedSigningNativeContent.requiresFullReader(document))

        document.metadata.values["ordinary"] = .null
        XCTAssertFalse(MobileGuidedSigningNativeContent.requiresFullReader(document))

        document.metadata.values["ordinary"] = authored
        XCTAssertTrue(MobileGuidedSigningNativeContent.requiresFullReader(document))
        XCTAssertTrue(document.body.contains("{{field:signature}}"))
    }

    func testNativeSigningFallbackRequiresFullReaderForEmbeddedImage() throws {
        let exchange = try makeSignedGuidedSigningExchange()
        var document = try exchange.document()
        XCTAssertFalse(MobileGuidedSigningNativeContent.requiresFullReader(document))
        document.body += "\n\n![Embedded](data:image/png;base64,AAAA)"
        XCTAssertTrue(MobileGuidedSigningNativeContent.requiresFullReader(document))
        XCTAssertTrue(try LeonardoLocalImagePolicy.signingReferences(in: document).isEmpty)
    }

    func testNativeSigningFallbackRequiresFullReaderForPageRubric() throws {
        let copy = try makeSignedGuidedSigningExchange()
        var document = try copy.document()
        XCTAssertFalse(MobileGuidedSigningNativeContent.requiresFullReader(document))
        let ink = try XCTUnwrap(copy.session.positions.values.first?.locations.first?.rubric)
        document.metadata.layout = LeonardoLayout(objects: [
            LeonardoGraphic(label: "Ordinary page rubric", rubric: ink)
        ])
        XCTAssertTrue(document.metadata.layout?.objects.first?.isValid == true)
        XCTAssertTrue(MobileGuidedSigningNativeContent.requiresFullReader(document))
    }

    func testNativeSigningContentSubstitutesValuesAndKeepsSealedResourceReferences() throws {
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let document = LeonardoDocument(
            body: "# Review copy\n\nSigner: {{field:name}}\n\nSignature: {{field:signature}}\n\n![Seal](assets/seal.png)",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "native-content-test", title: "Review copy", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "name": LeonardoFieldDefinition(type: .text, label: "Name"),
                    "signature": LeonardoFieldDefinition(
                        type: .rubric, label: "Signature", signerPosition: "owner"
                    )
                ],
                values: ["name": .string("Ada & Lovelace")]
            )
        )

        let readable = MobileGuidedSigningNativeContent.readableBody(from: document)
        XCTAssertTrue(readable.contains("Ada & Lovelace"))
        XCTAssertFalse(readable.contains("&#38;"))
        XCTAssertFalse(readable.contains("{{field:name}}"))
        XCTAssertEqual(
            MobileGuidedSigningNativeContent.referencedResourceReferences(from: document),
            ["assets/seal.png"]
        )

        let session = try LeonardoGuidedSigningSession(
            document: document, at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let target = try XCTUnwrap(session.targets(for: "owner", document: document).first)
        XCTAssertEqual(
            MobileGuidedSigningTargetKey.make(fieldID: target.fieldID, occurrence: target.occurrence),
            "signature#0"
        )
    }

    func testTrustedSignedReaderRendersVerifiedRubricOverlay() async throws {
        let exchange = try makeSignedGuidedSigningExchange()
        let document = try exchange.document()
        let resources = try exchange.signingResources()
        let trustStore = try LeonardoSigningTrustRegistry(credentials: exchange.trustedCredentials)
        XCTAssertEqual(
            exchange.session.signatureVerification(
                document: document, resources: resources, trustStore: trustStore
            )["owner"],
            .valid
        )

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        var available = Set<String>()
        let binding = Binding<Set<String>>(
            get: { available },
            set: { available = $0 }
        )
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MobileGuidedSigningDocumentReader(
                document: document,
                resources: resources,
                session: exchange.session,
                trustedCredentials: exchange.trustedCredentials,
                trustAccepted: true,
                focusTarget: nil,
                availableTargetKeys: binding,
                onFocusConsumed: {}
            )
        })
        window.makeKeyAndVisible()

        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        var snapshot: [String: Any] = [:]
        repeat {
            if let web = findWebView(window),
               let value = try? await web.evaluateJavaScript("""
                (() => ({
                  heading: document.querySelector('h1')?.textContent || '',
                  guidedFields: document.querySelectorAll('.leonardo-guided-signing-field').length,
                  overlaySVGs: document.querySelectorAll('.leonardo-guided-signing-field svg').length,
                  overlayLines: document.querySelectorAll('.leonardo-guided-signing-field svg line').length
                }))()
                """) as? [String: Any] {
                snapshot = value
                if snapshot["heading"] as? String == "Mobile signing practice",
                   (snapshot["guidedFields"] as? Int ?? 0) > 0,
                   (snapshot["overlaySVGs"] as? Int ?? 0) > 0,
                   (snapshot["overlayLines"] as? Int ?? 0) > 0,
                   available.contains("signature#0") {
                    return
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        XCTFail("Trusted signed reader did not render its verified rubric overlay (snapshot: \(snapshot), available: \(available.sorted()))")
    }

    func testVerifiedIncomingAdvanceSurvivesReopeningTheOlderCopy() async throws {
        let fixture = try makeGuidedSigningExchanges()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LeonardoSigningStore(directoryURL: root)
        let document = try fixture.signed.document()
        let location = "mobile://fixture/document"
        let baseline = try fixture.original.reboundSession(onto: nil, documentLocation: location)
        try await store.saveSession(baseline, replacing: nil)

        var withExtraResource = try XCTUnwrap(JSONSerialization.jsonObject(
            with: LeonardoSigningExchange.encoded(fixture.signed)
        ) as? [String: Any])
        withExtraResource["resources"] = [["reference": "unreferenced.png", "bytes": Data([1]).base64EncodedString()]]
        XCTAssertThrowsError(try LeonardoSigningExchange.decoded(JSONSerialization.data(withJSONObject: withExtraResource)))
        let afterRejection = try await store.session(id: baseline.id)
        XCTAssertEqual(afterRejection, baseline)

        let emptyTrust = try LeonardoSigningTrustRegistry(credentials: [])
        let untrusted = try await MobileGuidedSigningView.restoreSigningProgress(
            exchange: fixture.signed, document: document, resources: [], localDocumentLocation: location,
            store: store, trustStore: emptyTrust
        )
        XCTAssertEqual(untrusted.baseline, baseline)
        let beforeTrust = try await store.session(id: baseline.id)
        XCTAssertEqual(beforeTrust, baseline)

        let trusted = try LeonardoSigningTrustRegistry(credentials: fixture.signed.trustedCredentials)
        let accepted = try await MobileGuidedSigningView.restoreSigningProgress(
            exchange: fixture.signed, document: document, resources: [], localDocumentLocation: location,
            store: store, trustStore: trusted
        )
        XCTAssertTrue(accepted.session.isComplete)
        XCTAssertEqual(accepted.baseline, accepted.session)
        let reopened = try await MobileGuidedSigningView.restoreSigningProgress(
            exchange: fixture.original, document: document, resources: [], localDocumentLocation: location,
            store: LeonardoSigningStore(directoryURL: root), trustStore: trusted
        )
        XCTAssertEqual(reopened.session, accepted.session)
        do {
            try await store.saveSession(baseline, replacing: baseline)
            XCTFail("An older view may not overwrite the verified advance")
        } catch LeonardoSigningError.staleStorage {}
    }

    func testReceivedUnsignedLocationsCannotCompleteReview() async throws {
        let fixture = try makeGuidedSigningExchanges()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LeonardoSigningStore(directoryURL: root)
        let document = try fixture.signed.document()
        let location = "mobile://fixture/document"
        let trusted = try LeonardoSigningTrustRegistry(credentials: fixture.reviewed.trustedCredentials)
        let received = try await MobileGuidedSigningView.restoreSigningProgress(
            exchange: fixture.reviewed, document: document, resources: [], localDocumentLocation: location,
            store: store, trustStore: trusted
        )
        XCTAssertNil(received.session.snapshot)
        XCTAssertEqual(received.session.positions["owner"]?.state, .pending)
        XCTAssertNil(received.session.positions["owner"]?.assignment)
        XCTAssertTrue(try XCTUnwrap(received.session.positions["owner"]).locations.isEmpty)

        var local = fixture.reviewed.session
        local.documentLocation = location
        try await store.saveSession(local, replacing: nil)
        let reopened = try await MobileGuidedSigningView.restoreSigningProgress(
            exchange: fixture.reviewed, document: document, resources: [], localDocumentLocation: location,
            store: store, trustStore: trusted
        )
        XCTAssertEqual(reopened.session, local)
        XCTAssertEqual(reopened.session.positions["owner"]?.state, .readyToSign)
    }

    private func makeSignedGuidedSigningExchange() throws -> LeonardoSigningExchange {
        try makeGuidedSigningExchanges().signed
    }

    private func makeGuidedSigningExchanges() throws
        -> (original: LeonardoSigningExchange, reviewed: LeonardoSigningExchange, signed: LeonardoSigningExchange) {
        let declaration = LeonardoSigningDeclaration(positions: [
            LeonardoSignerPosition(id: "owner", label: "Owner")
        ])
        let document = LeonardoDocument(
            body: "# Mobile signing practice\n\nPlease sign here: {{field:signature}}",
            metadata: LeonardoMetadata(
                formatVersion: LeonardoFormat.signingVersion,
                document: LeonardoDocumentDescriptor(
                    id: "signed-mobile-reader", title: "Mobile signing practice", kind: .form,
                    revision: 1, signing: declaration
                ),
                fields: [
                    "signature": LeonardoFieldDefinition(
                        type: .rubric, label: "Signature", required: true, signerPosition: "owner"
                    )
                ]
            )
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        var session = try LeonardoGuidedSigningSession(document: document, at: date)
        let original = try LeonardoSigningExchange(document: document, session: session, trustedCredentials: [], at: date)
        let keyPair = LeonardoSigningKeyPair(credentialID: "fixture-owner")
        let profile = LeonardoSignerProfile(
            displayName: "Ana Example",
            identity: LeonardoDeclaredIdentity(
                fullName: "Ana Example", documentType: .nationalID, documentNumber: "QA-0001"
            )
        )
        let authorization = try LeonardoSigningAuthorization(
            positionID: "owner", profileID: profile.id, credentialID: keyPair.credential.id,
            confirmedAt: date, explicitlyConfirmed: true
        )
        try session.assign(
            positionID: "owner", profile: profile, credential: keyPair.credential,
            authorization: authorization, at: date
        )
        let targets = try session.begin(positionID: "owner", document: document)
        let rubric = LeonardoRubric(strokes: [LeonardoInkStroke(
            color: "#111111", width: 2, style: .solid,
            points: [LeonardoInkPoint(x: 20, y: 20), LeonardoInkPoint(x: 120, y: 80)]
        )])
        let target = try XCTUnwrap(targets.first)
        try session.confirmLocation(
            positionID: "owner", fieldID: target.fieldID, occurrence: target.occurrence,
            document: document, contextRead: true, rubric: rubric, at: date
        )
        let reviewed = try LeonardoSigningExchange(
            document: document, session: session,
            trustedCredentials: [keyPair.credential], at: date
        )
        let trustStore = try LeonardoSigningTrustRegistry(credentials: [keyPair.credential])
        _ = try session.sign(
            positionID: "owner", keyPair: keyPair, document: document,
            trustStore: trustStore, at: date
        )
        let signed = try LeonardoSigningExchange(
            document: document, session: session,
            trustedCredentials: [keyPair.credential], at: date
        )
        return (original, reviewed, signed)
    }

    private func assertReadOnlyMobilePreview(library: MobileLibrary, projectID: UUID, file: CorpusFile,
                                             expectedHeading: String, expectedValue: String?) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MobileDocumentView(library: library, projectID: projectID, file: file)
                .navigationBarTitleDisplayMode(.inline)
        })
        window.makeKeyAndVisible()

        // A cold hosted simulator also has to start the WebKit content process.
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        var snapshot: [String: Any]?
        repeat {
            if let preview = findWebView(window),
               let result = try? await preview.evaluateJavaScript("""
                (() => ({
                  heading: document.querySelector('h1')?.textContent || '',
                  body: document.body.innerText,
                  fieldCount: document.querySelectorAll('.leonardo-form-field').length,
                  value: document.querySelector('.leonardo-field-output')?.textContent || '',
                  controlsDisabled: Array.from(document.querySelectorAll('.leonardo-form-field input, .leonardo-form-field textarea, .leonardo-form-field select')).every(control => control.disabled)
                }))()
                """) as? [String: Any], result["heading"] as? String == expectedHeading {
                snapshot = result
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline

        let rendered = try XCTUnwrap(snapshot, "Little Leonardo did not render \(file.path) through the Leonardo-aware reader")
        let preview = try XCTUnwrap(findWebView(window))
        XCTAssertTrue((rendered["body"] as? String)?.contains(expectedHeading) == true)
        if let expectedValue {
            XCTAssertEqual(rendered["value"] as? String, expectedValue)
            XCTAssertGreaterThan(rendered["fieldCount"] as? Int ?? 0, 0)
            XCTAssertTrue(rendered["controlsDisabled"] as? Bool == true,
                          "Received MDLR fields must stay read-only in Little Leonardo")
        }
    }

    private func waitUntilReady(_ controller: MarkdownPreviewController) async throws {
        for _ in 0..<200 {
            if controller.isReady { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The real WKWebView renderer did not become ready")
    }

    private func findWebView(_ view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        return view.subviews.lazy.compactMap(findWebView).first
    }

}

private actor ReaderSpacingCredentials: DeviceCredentialStore {
    func credential(deviceID: UUID) async throws -> String? { "synthetic-offline-credential" }
    func save(_ credential: String, deviceID: UUID) async throws {}
    func remove(deviceID: UUID) async throws {}
}
