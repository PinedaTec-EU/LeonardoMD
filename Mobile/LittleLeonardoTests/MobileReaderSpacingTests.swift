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

    func testSynchronizedDocumentViewUsesCompactReaderSpacing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let corpus = root.appendingPathComponent("Corpus")
        let projectID = UUID()
        let file = try CorpusFile(path: "01-Prueba-visual.md", content: Data(
            "# Little Leonardo · prueba visual\n\nDocumento de prueba sin datos personales.\n\n## Imagen local\n\nLectura sincronizada de prueba.".utf8))
        let project = try OfflineProject(id: projectID, name: "QA397", mode: .direct,
            scope: CorpusScope(folder: ""), snapshot: CorpusSnapshot(revision: "qa397", files: [file]))
        try await OfflineCorpusStore(root: corpus).save(project)
        let connection = MobileDirectConnection(deviceID: UUID(), endpoint: URL(string: "https://127.0.0.1:40882")!,
            fingerprint: Data(repeating: 7, count: 32), projectIDs: [projectID], comparisonCode: nil, capabilities: [])
        try MobileDirectConnectionStore(url: root.appendingPathComponent("connections.json")).save([connection])
        let library = MobileLibrary(rootURL: corpus, credentials: ReaderSpacingCredentials())
        await library.reload()
        XCTAssertEqual(library.projects.count, 1)
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
        for _ in 0..<150 {
            if let web = findWebView(window), let values = try? await metrics(web) {
                XCTAssertLessThanOrEqual(try XCTUnwrap(values["headingTop"]), 32)
                attach(window, name: "Synchronized document reader")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The synchronized document did not render")
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

    func testSignedGuidedSigningViewPresentsReaderOutsideList() async throws {
        let exchange = try makeSignedGuidedSigningExchange()
        XCTAssertTrue(exchange.session.isComplete)
        XCTAssertEqual(exchange.trustedCredentials.count, 1)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = MobileLibrary(
            rootURL: root.appendingPathComponent("Corpus", isDirectory: true),
            credentials: ReaderSpacingCredentials()
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MobileGuidedSigningView(
                library: library,
                exchange: exchange,
                initiallyShowingDocumentReader: true
            )
        })
        window.makeKeyAndVisible()

        // This integration test checks that the reader is presented outside
        // the form list. Both the immediately visible native reader and the
        // optional WebKit replacement are valid presentations. Other tests
        // verify the heading, exact targets, and the trusted rubric overlay.
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        repeat {
            if let presented = window.rootViewController?.presentedViewController,
               presented.isViewLoaded, presented.view.window === window,
               presented is UIAlertController == false,
               !presented.isBeingPresented {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        XCTFail("The signed-guided reader was not presented outside the form list")
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

    private func makeSignedGuidedSigningExchange() throws -> LeonardoSigningExchange {
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
        let trustStore = try LeonardoSigningTrustRegistry(credentials: [keyPair.credential])
        _ = try session.sign(
            positionID: "owner", keyPair: keyPair, document: document,
            trustStore: trustStore, at: date
        )
        return try LeonardoSigningExchange(
            document: document, session: session,
            trustedCredentials: [keyPair.credential], at: date
        )
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
        let previewImage = try await captureWebView(preview)
        let attachment = XCTAttachment(image: previewImage)
        attachment.name = "Little Leonardo read-only \((file.path as NSString).pathExtension.uppercased()) preview"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let expectedValue {
            XCTAssertEqual(rendered["value"] as? String, expectedValue)
            XCTAssertGreaterThan(rendered["fieldCount"] as? Int ?? 0, 0)
            XCTAssertTrue(rendered["controlsDisabled"] as? Bool == true,
                          "Received MDLR fields must stay read-only in Little Leonardo")
        }
    }

    func testCompactReaderKeepsFirstHeadingNearContentTopAndLaterSectionsSpaced() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        let controller = MarkdownPreviewController()
        let content = "# Little Leonardo · prueba visual\n\nDocumento de prueba sin datos personales.\n\n## Imagen local\n\n" +
            String(repeating: "Lectura de prueba para comprobar el desplazamiento.\n\n", count: 30)
        let configuration = MarkdownPreviewConfiguration(appearance: .leonardoClassic)
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MarkdownPreview(content: content, configuration: configuration, controller: controller)
                .classicSurface().navigationTitle("01-Prueba-visual.md").navigationBarTitleDisplayMode(.inline)
        })
        window.makeKeyAndVisible()
        try await waitUntilReady(controller)
        let web = try XCTUnwrap(findWebView(window))
        let original = try await metrics(web)
        attach(window, name: "Default reader spacing")

        var compact = configuration
        compact.compactFirstHeading = true
        controller.update(content: content, configuration: compact)
        // Readiness is published asynchronously after applying the new configuration.
        try await Task.sleep(for: .milliseconds(150))
        try await waitUntilReady(controller)
        let adjusted = try await metrics(web)
        attach(window, name: "Compact reader spacing")
        let record = try JSONSerialization.data(withJSONObject: ["default": original, "compact": adjusted], options: [.sortedKeys])
        let facts = XCTAttachment(data: record, uniformTypeIdentifier: "public.json")
        facts.name = "Measured reader spacing"; facts.lifetime = .keepAlways; add(facts)
        XCTAssertLessThanOrEqual(try XCTUnwrap(adjusted["headingTop"]), 32)
        XCTAssertLessThan(try XCTUnwrap(adjusted["headingTop"]), try XCTUnwrap(original["headingTop"]))
        XCTAssertEqual(adjusted["laterHeadingMargin"], original["laterHeadingMargin"])
        XCTAssertGreaterThan(try XCTUnwrap(adjusted["scrollHeight"]), try XCTUnwrap(adjusted["viewportHeight"]))

        controller.update(content: content, configuration: configuration)
        try await Task.sleep(for: .milliseconds(150))
        try await waitUntilReady(controller)
        let restored = try await metrics(web)
        XCTAssertEqual(try XCTUnwrap(restored["headingTop"]), try XCTUnwrap(original["headingTop"]), accuracy: 0.5)
    }

    func testOnDemandReaderKeepsAcceptedCompactHeadingSpacing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = DownloadLibrary(cache: OnDemandCache(root: root))
        let project = SharedProjectDescriptor(id: UUID(), name: "On-demand reader QA", scope: try CorpusScope(folder: ""))
        let file = CorpusFile(path: "read.md", content: Data("# On-demand reader\n\nSynthetic reading content.\n\n## Later section\n\nNormal section spacing.".utf8))
        try await library.update(id: project.id, descriptor: project, catalogue: RemoteProjectCatalogue(files: [RemoteFileEntry(file: file)]))
        library.fetch = { _, _ in file }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let priorWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        defer { window.isHidden = true; priorWindow?.makeKeyAndVisible() }
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            RemoteDocumentPreview(library: library, projectID: project.id, entry: RemoteFileEntry(file: file),
                appearance: .leonardoClassic, compactFirstHeading: true)
                .classicSurface().navigationBarTitleDisplayMode(.inline)
        })
        window.makeKeyAndVisible()
        for _ in 0..<150 {
            if let web = findWebView(window), let values = try? await metrics(web) {
                XCTAssertEqual(try XCTUnwrap(values["headingTop"]), 16, accuracy: 1)
                XCTAssertGreaterThan(try XCTUnwrap(values["laterHeadingMargin"]), 0)
                let data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
                let record = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                record.name = "On-demand measured reader spacing"; record.lifetime = .keepAlways; add(record)
                attach(window, name: "On-demand synchronized document reader")
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("The real on-demand preview did not render")
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

    private func metrics(_ web: WKWebView) async throws -> [String: Double] {
        let result = try await web.evaluateJavaScript("""
        (() => ({headingTop: document.querySelector('h1').getBoundingClientRect().top,
          laterHeadingMargin: parseFloat(getComputedStyle(document.querySelector('h2')).marginTop),
          scrollHeight: document.documentElement.scrollHeight, viewportHeight: window.innerHeight}))()
        """)
        return try XCTUnwrap(result as? [String: Double])
    }

    private func captureWebView(_ web: WKWebView) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            web.takeSnapshot(with: nil) { image, error in
                if let error { continuation.resume(throwing: error) }
                else if let image { continuation.resume(returning: image) }
                else { continuation.resume(throwing: CocoaError(.fileReadUnknown)) }
            }
        }
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private actor ReaderSpacingCredentials: DeviceCredentialStore {
    func credential(deviceID: UUID) async throws -> String? { "synthetic-offline-credential" }
    func save(_ credential: String, deviceID: UUID) async throws {}
    func remove(deviceID: UUID) async throws {}
}
