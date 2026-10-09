# Little Leonardo

Implementation tracking: [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92).

## Agreed product contract

Little Leonardo projects choose direct read-only synchronization or Git editing, including direct mode for an existing Git project. Desktop-to-desktop direct synchronization additionally supports offline editing/creation/deletion with manual reconciliation. Direct connections require an authorized private-network path (LAN, or configured VPN for desktop peers); Git can operate over the Internet. Desktop peer work is tracked in [#101](https://github.com/PinedaTec-EU/LeonardoMD/issues/101).

The desktop service is explicitly enabled, off by default. Pairing supports a unique QR or IP/port and a cross-checked code. Projects are explicitly authorized. Device credentials stay in platform secure storage, outside portable configuration. Turning off the service retains mobile corpus; revocation requests deletion on the next reachable contact and rejects further document access. Offline deletion cannot be guaranteed before contact. Git copies are independent of direct revocation.

Direct snapshots include permitted documents/resources and open unsaved buffers. Mobile caches them for offline reading and explains the Git requirement when Edit is pressed. Both manual synchronization and a configurable interval are available; intervals operate while the iOS app can execute, without promising continuous background timers.

Git import selects a folder before transferring file contents and remembers it. Sparse checkout alone is insufficient: partial transfer must be supported by both server and iOS adapter. Never fall back silently to full clone. Hidden files, credentials, build outputs and path escapes are excluded. Offline creation, editing and deletion remain inside the selected corpus.

Send changes publishes a device-specific branch before sending an optional paired-desktop notification. Publication and notification are separate outcomes. Desktop also discovers branches by fetching, offers diffs and user-controlled reconciliation, and preserves unsaved desktop work. Mobile distinguishes local changes, sent work and integrated work. Further offline edits survive incorporation of a previous send; overlapping edits remain pending for desktop resolution.

## Implementation status

`LeonardoSync` is an independent shared SwiftPM library targeting macOS 14 and iOS 17. It contains corpus path/content limits, direct read-only and Git-editable offline state, atomic cache persistence, selected folder/document reading with unsaved-buffer overlays, and an editable desktop-peer copy model with manual reconciliation. Its regression tests cover escapes, hidden/build exclusions, symlinks, case aliases, size limits, restart, deletion and later edits during integration.

The native iPhone/iPad target builds on iOS 17+. Direct enrollment, desktop consent/service lifecycle, persistent TLS identity, read-only offline corpus and mobile Markdown preview are implemented with focused TLS and native UI evidence. HTTPS Git supports explicit branch/folder enrollment and clean-copy refresh; dirty or sent work is retained. Native commit/tree rewriting and pack output pass actual Git SHA-1/SHA-256 validation. These are partial implementation results: full native import/revocation/reconciliation acceptance, successful mobile publication, SSH and desktop peer editing/reconciliation remain pending. Later checkpoints below record the evidence and limitations of each subsystem.

## Boundaries to retain

- Selected scope governs reads, edits and publication, not just the mobile file browser.
- Publication must succeed before notification; notification delivery never substitutes for Git discovery.
- Integration updates must identify the published commit whose work was accepted, rather than trusting any new remote revision.
- Invalid or oversized snapshots fail atomically rather than silently delivering an incomplete corpus.
- Reconciliation must preserve local work; neither desktop buffers nor mobile edits are implicitly discarded.

## Native iOS build

Open `Mobile/LittleLeonardo.xcodeproj` and select the shared `LittleLeonardo` scheme. Simulator builds do not require signing credentials:

```sh
xcodebuild -project Mobile/LittleLeonardo.xcodeproj -scheme LittleLeonardo -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/little-ios CODE_SIGNING_ALLOWED=NO build
```

CI builds this target alongside the macOS suite. Mobile sources are included in the release ledger's versioned path scope. Device installation and distribution require the owner's Apple signing configuration; neither is claimed by simulator validation.

## Pairing policy checkpoint

`PairingRegistry` requires desktop consent with matching comparison code and a non-empty project grant. QR invitations expire after five minutes and are single-use; regenerating a QR invalidates the prior invitation. Manual pairing requests require the same explicit desktop consent. Authorization checks bind a device credential to the approved projects. Revocation persists, returns cleanup status only to the matching credential, and prevents document access. Disabling the service clears pending invitations/requests while preserving paired-device metadata.

Raw bearer credentials are generated with the platform secure random source and stored by `SecureCredentialStore` in device-only, non-synchronizing Keychain entries. The registry persists credential hashes in a bounded, atomic host-local file with owner permissions. The shared HTTPS transport now verifies a certificate pin and its explicit trust anchor before credential exchange. Native enrollment screens must obtain that pin from QR or an independently calculated cross-check; those screens are pending. No plaintext LAN access is introduced.

Filesystem adapters resolve the trusted configured directory and preserve the final entry for symlink checks. Do not reject legitimate host-root aliases or normalize an untrusted descendant before checking it. Regression: [#96](https://github.com/PinedaTec-EU/LeonardoMD/issues/96).

## HTTPS transport checkpoint

`LeonardoSyncTransport` uses Network.framework for an HTTP/1.1 TLS listener bound to one explicit private/local IP literal, plus a pinned URLSession client. It rejects wildcard/public bindings, redirects, duplicate or ambiguous framing headers, oversized requests/responses and wrong certificate pins. Certificate trust retains anchored signature/validity evaluation. Client response bytes are bounded while streaming. Header and operation deadlines and connection limits bound work. Logs contain method/status/lifecycle fields, not credentials or corpus contents.

`DirectSyncAuthority` persists consent changes before publishing them, exposes only granted project descriptors, and rechecks authorization after asynchronous corpus reads. `DirectHTTPSRouter` exposes pairing request, own-device status and authorized snapshot routes; approval is exclusively a desktop-side application action. A revoked device receives cleanup status, but no snapshot.

Real loopback TLS regressions exercise disabled service, pending request, approval, unsaved-buffer snapshot transfer, revocation, wrong pin and response bounds. Additional domain tests cover failed persistence and revocation during a suspended snapshot read. These prove transport/application contracts, not end-user desktop/iOS pairing or physical-device networking.

The manual comparison code binds the observed certificate fingerprint, client credential digest and request ID. Both UIs must compute/display their own value; copying the remote code would invalidate the protection. Preventive correction: [#97](https://github.com/PinedaTec-EU/LeonardoMD/issues/97). Streaming requests explicitly use the canonical TLS task delegate: [#98](https://github.com/PinedaTec-EU/LeonardoMD/issues/98).

Desktop integration now includes the default-off global preference, explicit project grants, QR generation, device approval/rejection/revocation and service lifecycle wiring. The server identity is an encrypted owner-only PKCS#12 archive with its password in device-local Keychain; missing credentials fail rather than silently rotating the pin. Three desktop adapter tests cover restart identity continuity, actual pinned TLS, missing-password preservation and no identity provisioning while disabled. Two QR tests cover round-trip, expiry and malformed/external endpoint rejection. Native end-user UI acceptance, QR/manual enrollment on iOS, mobile secure-credential use and cache cleanup, and manual/configured-interval refresh remain pending. Git transport, publication/notifications and desktop reconciliation remain separate unfinished requirements.

## Mobile enrollment checkpoint

The iOS library accepts a pasted QR link, computes its comparison code independently and lets the user request desktop consent. Manual refresh downloads only approved project snapshots using the pinned HTTPS client. Connection metadata survives relaunch without retaining QR invitation secrets; credentials live in device-only Keychain. Authorized direct snapshots are cached for offline reading. Revocation removes owned caches and hides an open reader; disabling or unreachable service retains the cache. A real TLS regression covers pending/approved/revoked states and unsaved-buffer download. Simulator compilation passes, but native interaction, durable mobile cleanup/retry evidence, camera scanning and IP/port manual pairing are still pending. Direct refresh supports manual operation or a persisted 1/5/15/30/60-minute interval while the app is active; background execution is not assumed. Interval and native cleanup behavior still require runtime acceptance.

## Offline archive regression

[#99](https://github.com/PinedaTec-EU/LeonardoMD/issues/99) records a valid near-limit corpus that could be saved but not reopened. The encoded bound now accounts for all three base/current/published collections, base64 expansion and escaped metadata, with checked integer arithmetic. Paths are bounded to 4 KiB, revisions to 256 bytes and stored project names to 1 KiB to make the metadata allowance finite. Save and load use the same encoded bound. The published-baseline restart regression and unrepresentable-limit rejection pass.

## Camera scanner checkpoint

The pairing screen can scan a QR with Apple VisionKit. Camera permission is requested only after the user opens the scanner. Unsupported/restricted hardware offers pasted-link enrollment; cancellation dismantles the scanner and stops capture. Only a valid, unexpired Little Leonardo QR is accepted, and reading it does not automatically authorize or start the network connection. The iOS Simulator UI test opens the scanner, verifies its unavailable fallback, cancels it, and verifies no connection request was initiated. Its real screenshot was inspected from `/tmp/little-camera-ui.xcresult`. Physical-camera capture and permission-denial behavior are implemented but not verified on a physical device.

## Manual address pairing checkpoint

The iOS pairing form accepts a private/local IP literal and port. `ServerIdentityProbe` observes the TLS certificate, checks its anchored validity and cancels the handshake: no HTTP request or application credentials are sent during discovery. The observed fingerprint is not independently authenticated at this stage. Subsequent pairing requests pin that exact fingerprint, and project access requires desktop approval after comparing the independently computed codes. The probe never follows redirects or accepts wildcard/public/DNS endpoints. A real loopback test verifies zero routed HTTP requests during discovery and pending/approved manual enrollment. Two native Simulator UI tests pass for QR cancellation and switching between QR/manual entry. Full desktop-to-mobile UI acceptance, durable mobile revocation/retry acceptance and Git remain unfinished.

## Desktop preference acceptance checkpoint

Little Leonardo service/project/device consent labels are present in both desktop catalogs and follow the selected English/Spanish app language. Nine localization checks pass, including two inspected native `NSHostingView` captures of the disabled service panel from an isolated temporary configuration. They do not prove packaged application startup or enabled device-consent UI. The fixture asserts no TLS identity is created while disabled. Seven configuration-store tests pass; new regressions verify legacy preferences default off and independent stale-window project/port changes preserve explicit service consent.

## Native Markdown reader checkpoint

`LeonardoRender` now supports macOS and iOS through native WebKit hosts. The desktop process-based Git adapter remains macOS-only; this does not implement mobile Git. The mobile reader renders Markdown with bundled sanitization, diagrams/math and selected-corpus image assets from immutable memory. It can switch to source text for reading/editing. Mobile preview CSP blocks remote image loads; hyperlinks are currently blocked and navigation remains unfinished. The memory asset handler never falls back to disk when a memory corpus is supplied.

Twelve renderer tests and a real macOS WebKit integration test pass; the latter renders a table and cached SVG, then verifies image removal after clearing the asset source. An iOS Simulator UI test passes for rendered heading/table/image and source toggle. Its inspected capture is in `/tmp/little-markdown-ios-ui.xcresult`; the corpus is an explicitly seeded synthetic `QA · Markdown` fixture, not an enrollment transfer or real user project. That UI test skips when the fixture is absent. Full mobile pairing/refresh/revocation and hyperlink acceptance remain pending.

## Git protocol foundation checkpoint

`LeonardoGit` starts the native iOS/macOS Git engine with binary-safe bounded pkt-line framing and strict protocol-v2 capability parsing. A metadata request is generated only when `ls-refs`, `fetch=shallow filter` and a supported object format are advertised. It requests the selected tip with `deepen 1` and `filter blob:none`; no unfiltered fallback is generated. Framing follows [Git protocol common](https://git-scm.com/docs/gitprotocol-common) and negotiation follows [protocol v2](https://git-scm.com/docs/protocol-v2).

Four tests pass, including real `git upload-pack` advertisements with filtering off/on and an actual metadata fetch from a repository containing a selected document plus a 16 MiB code fixture. Importing that pack into a clean bare receiver and enumerating objects finds only commits/trees and zero blobs. Object-type evidence is required here: transfer byte count alone could conceal a highly compressed large file. The module also compiles in the iOS target. This is protocol groundwork, not a working mobile Git clone: HTTPS/SSH transports, pack/object storage, folder discovery, selected-blob fetch, publication and reconciliation are unfinished.

## Git reference discovery checkpoint

Protocol-v2 `ls-refs` requests branch references and symbolic HEAD, including unborn HEAD when advertised. Replies enforce framing, negotiated object-ID length, valid Git ref names, unique names and valid attributes. Because Git permits the server to ignore `ref-prefix`, the client also filters returned references to HEAD and branch categories. Six wire tests pass; real repositories verify SHA-1/SHA-256, unborn HEAD and Unicode branch names, while `git check-ref-format` checks the validator cases. This discovers refs only, not folders or contents. HTTP/SSH connection, pack decoding, selected-folder import and publishing still remain unfinished.

## Git fetch-response checkpoint

Fresh `fetch` replies are decoded as ordered shallow-boundary and packfile sections. The client separates sideband progress from binary pack data, rejects fatal/unknown channels and unsolicited packfile URI sections, and enforces wire, pack and object-count bounds. It supports the optional stateless response-end marker, checks PACK header/version and verifies the SHA-1/SHA-256 trailer before exposing pack bytes. This validates the envelope and pack integrity before object decoding.

Eight Git tests pass, including real SHA-1/SHA-256 packs, corrupted trailers, split binary packets, fatal channels, URI injection and size limits. The existing metadata regression now uses this parser before importing with Git CLI and still proves zero file blobs transferred. The module compiles in the iOS target. Network transport, native pack storage/decoding, folder import, publication and reconciliation remain pending.

## Native pack decoding checkpoint

Bounded system-zlib decompression and Git delta reconstruction now decode complete commit/tree/blob/tag objects, offset deltas and reference deltas. Resolution uses dependency queues, rejects missing bases (no thin-pack request is made), and bounds individual objects, aggregate inflated content and delta-chain depth. Canonical object IDs use Git type/length headers and the negotiated SHA-1/SHA-256 hash.

Seven wire tests pass, including comparison of all 36 objects in actual Git-generated packs against `git cat-file`, for both delta encodings; the fixture asserts that deltas really exist. Five focused delta/inflate tests cover copy/insertion instructions, sliced buffers, truncation, declared sizes and exact compressed-stream consumption. iOS compilation is checked separately. Network transport, scoped folder import, publication and desktop reconciliation remain unfinished.

## Selected-folder metadata checkpoint

`GitTree` parses bounded binary trees, distinguishing directories, regular/executable files, symbolic links and submodules. It rejects malformed modes, traversal/control names, truncated identifiers and case/Unicode aliases. `GitFolderIndex` follows the selected commit's root tree, lists immediate subdirectories, and enumerates only allowed document/resource paths under an explicit `CorpusScope`; it omits links and submodules. Missing trees fail instead of widening the scope.

Ten focused tree/wire tests pass. A real repository containing a 16 MiB code file discovers `docs` and selects only `docs/note.md` from a blob-free metadata pack. This establishes the selection boundary, not a working network import; HTTPS/SSH, fetching selected blobs, persistent Git state, publishing and desktop reconciliation remain pending.

## Selective remote-reader checkpoint

`GitRemoteReader` now separates reference discovery, blob-free commit/tree metadata and explicitly selected corpus transfer. `selectedBlobRequest` wants only unique selected object IDs; `GitSelectedCorpus` rejects missing or unsolicited blobs and validates the final scoped snapshot. Empty selections make no content request. A server rejecting reachable-object wants fails; there is no full-repository fallback.

`GitHTTPTransport` implements smart HTTPS using normal system TLS trust, ephemeral sessions, explicit optional Basic credentials (including host-issued tokens), protocol-v2 headers, strict MIME/status checks and bounded streamed responses. It refuses redirects and implicit authentication challenges; credentials are not placed in URLs or logs. Application Keychain enrollment, SSH and mobile Git UI integration remain pending.

Eleven HTTP/wire tests pass. HTTP tests use a URLProtocol fixture and therefore do not establish real TLS/network interoperability. A real `git upload-pack` fixture verifies the reader's three-stage ordering and imports only the selected Markdown document while leaving a 16 MiB unselected file out. The fixture explicitly enables reachable-object wants. Full native HTTPS/SSH host acceptance, mobile persistence/publication and desktop reconciliation remain pending.

## iOS Git enrollment checkpoint

The mobile library now offers a separate Git connection sheet: smart HTTPS endpoint, optional username/token, explicit branch selection, metadata-only folder navigation and an explicit import button. Scoped Git corpora are saved through the existing offline store; validated project/endpoint/branch/folder descriptors are persisted separately with no secrets. Keychain access is shared by direct and Git credential adapters using separate services and device-only non-synchronizable items. Cancelled screen operations do not intentionally initiate an import; installation failures attempt removal of partial corpus/descriptor/secret state.

Eight focused storage/HTTP/envelope tests pass with explicit live HTTPS QA enabled. The live test reads the public LeonardoMD repository through actual system-trusted HTTPS and imports only `doc`; it does not write to the remote. A real iOS Simulator UI test verifies the empty-endpoint guard and cancellation and captures the Git credential form. It does not prove the entire native branch/folder/import flow or authenticated Keychain enrollment.

The live test found GitHub's service-envelope incompatibility, tracked in [#100](https://github.com/PinedaTec-EU/LeonardoMD/issues/100); the strict parser now accepts the exact upload-pack envelope plus flush and rejects mismatched/nested/malformed envelopes. Full native import acceptance, Git refresh/reconciliation, sending commits, SSH and desktop integration remain pending. Git is still unfinished even though imported corpora support local editing.

## Git refresh checkpoint

Manual and foreground-interval synchronization now also refreshes persisted HTTPS Git projects using their selected branch and fixed folder. An unchanged tip skips content transfer; a clean copy accepts the new scoped snapshot atomically. Local edits block replacement: the app distinguishes unpublished edits from a changed remote requiring desktop reconciliation. A sent publication remains pending until future explicit integration evidence; advancing the remote branch alone never clears that state. Network/authentication failure retains the offline corpus.

Two domain tests verify atomic rejection of dirty, sent, direct and out-of-scope replacement. The real upload-pack reader regression additionally verifies unchanged, local-edit, remote-divergence, clean-update and awaiting-integration outcomes. Standalone sync settings expose the existing configurable foreground interval to Git-only users. Sending commits, receiving desktop integration evidence, SSH and full native Git acceptance remain pending.

## Scoped commit and pack-writing checkpoint

`GitCommitBuilder` builds a single-parent commit from a validated offline change set and its exact baseline metadata. Tree rewriting preserves untouched object IDs/modes, updates only scoped paths, removes empty directories and retains unsupported files, symlinks and submodule entries. Author identity/time are explicit inputs. Canonical object hashing is shared with pack decoding; bounded system-zlib compression writes complete-object packs with a verified format-specific checksum.

Real Git accepts these objects through `index-pack` and `fsck --full` for SHA-1 and SHA-256. Tests verify edit/create/delete/empty-file behavior, executable permissions, unchanged code/link/submodule entries and Git tree ordering. Pack round trips test deduplication, large headers, empty blobs, tampered identifiers and object/pack bounds.

This is local commit construction, not successful publication. The application must still persist baseline commit/tree metadata for sending after the remote branch advances, implement receive-pack negotiation/push/retry, save publication state only after confirmed acceptance and notify the desktop afterward. Desktop reconciliation and SSH remain pending.

## Durable Git baseline checkpoint

Baseline commit/tree objects are archived as bounded, checksummed packs under project ID and exact revision, with no file blobs or credentials. Loading verifies object hashes, object formats, complete tree dependencies and the requested commit identity. Import persists the baseline before exposing the corpus; clean refresh writes the new revision archive before saving the corpus, then removes unused older archives only after success. Interrupted refresh therefore leaves the previous corpus's baseline available.

Three archive tests cover SHA-1/SHA-256, exact-revision reopening, explicit retention, unrelated-file preservation, corruption, wrong identity, missing trees, blob rejection and symlink/path guards. Fetch-envelope and actual remote-reader regressions also pass. Application commit construction now consumes the durable baseline independently of the current server capability advertisement. Publication/retry and desktop reconciliation still remain unfinished.

## Desktop peer extension

The owner confirmed [#101](https://github.com/PinedaTec-EU/LeonardoMD/issues/101): pair Mac Studio/MacBook Pro (or other LeonardoMD instances), select folders and/or individual documents, and retain an editable offline copy on connection loss. Desktop direct mode supports creation/editing/deletion; reconnection requires manual base/local/remote reconciliation, preserving unsaved buffers. LAN and explicitly configured VPN/private-overlay connections are in scope. Mobile direct mode remains read-only. Domain/content selection is described below; desktop peer enrollment, client UI and remote write transport remain pending. Durable copy cache/materialization is described below. Current private-address policy must be extended and verified for relevant VPN routing without implicit public-interface exposure.

The shared `ManualReconciliation` comparison now captures base/local/remote snapshots and lists every changed path, including additions, deletions and unsaved buffers. Every change requires an explicit local/remote/merged-content/delete decision. Resolving checks both current snapshots against those reviewed, rejects incomplete or extraneous choices, and validates the final corpus for scope, limits and case aliases. It performs no filesystem writes. Two domain tests cover delete/edit conflicts, created files, unsaved-buffer preservation, stale comparisons and invalid merged results. Native peer lifecycle, reconciliation UI, exclusive remote write ownership and transport remain pending.

`CorpusSelection` represents explicit folders and individual documents, removes redundant descendant selections and rejects path escapes, excluded content and case aliases. The native Share action starts with no selection, offers a folder/document picker or explicit whole-project choice, and persists the resulting grant. `ProjectCorpusReader` traverses only selected folders, reads only selected documents, applies combined limits and rejects unselected buffers. The desktop source filters buffers before reading; the authority independently checks the snapshot against the grant. Direct revisions hash framed paths, bytes and draft flags, so unchanged reads keep a stable identity for reviewed comparisons.

`DesktopPeerCopy` supports selected offline edits, additions and deletions independently of the mobile read-only mode. Clean copies can refresh; dirty copies require reconciliation. A confirmed reconciliation must match the manually resolved corpus and the unchanged local comparison; invalid acknowledgement or later edits preserve the existing copy. Encoding/reopening validates the entire selection and corpus. This is a domain model, not a native two-Mac synchronization acceptance. Scope-focused tests and the full suite pass (188 XCTest cases, six optional skips, plus 12 renderer tests); the iOS target builds. Separate inspected native hosting captures cover empty/selected sharing states in English and Spanish without starting the synchronization service or another packaged app instance.

## Receive-pack publication checkpoint

`GitPublisher` now negotiates receive-pack references/capabilities, validates the selected object format, writes only the `refs/heads/little-leonardo/` namespace and requires report-status acceptance for the exact target branch. Its command carries the expected previous object ID, so a stale advertisement/branch state cannot be silently replaced. Retrying the exact prepared commit checks whether the remote branch already identifies it and avoids sending a duplicate pack. Device/project UUIDs generate a stable branch name. The wire contract follows [Git pack protocol](https://git-scm.com/docs/gitprotocol-pack).

Smart HTTPS now includes receive-pack advertisement and POST endpoints with the same TLS/credential/redirect policy as fetch, bounded upload bodies and bounded result streams. HTTP contract tests cover their headers, MIME and paths with a URLProtocol fixture; they do not establish a live authenticated HTTPS push.

Four push tests pass, including actual temporary bare repositories in both object formats. Git accepts branch creation/update, exact-commit retry does not send again, stale expected IDs fail, a rejecting pre-receive hook leaves the previous reference unchanged, and malformed status reports cannot count as acceptance. No production remote was written. Post-success desktop notification and reconciliation/SSH remain pending.

## Durable sending checkpoint

The iOS Send action freezes and persists an immutable project/device publication before any network write. The journal contains the exact commit identity, expected remote branch tip, scoped file identifiers and a bounded pack; reopening verifies the baseline and rebuilds the commit rather than trusting archived paths or identifiers. Pending intent blocks refresh of its baseline. Retrying preserves the original capture even if the user edits or reverts files afterward.

After receive-pack confirms acceptance (or finds that exact commit already accepted), the app saves publication state while retaining later local edits, records the branch tip and finally removes the journal. A pending journal survives network failure and interrupted acknowledgement; commit author name/email are configurable in sync settings. File permissions, tampering, immutable intent, scoped restoration and later edits are tested. Actual SHA-1/SHA-256 receive-pack fixtures simulate interruption after remote acceptance and verify one push, the captured remote content and durable later local edits. The iOS target builds; full native authenticated sending, desktop notification, integration receipts, manual reconciliation and SSH are still incomplete.

## Desktop offline persistence checkpoint

`DesktopPeerCopyStore` and `DesktopPeerWorkspaceAccess` define the persistence/working-directory boundaries. The macOS archive adapter saves both base and current corpus in bounded validated JSON. Writes rename a private 0600 temporary file into a 0700 directory; load checks file size before decoding, identity, selection, path aliases and corpus bounds. No credentials are stored with documents.

Initial working-directory materialization is staged and exposed only after archiving its copy. Files/resources are private and preserve bytes. Reopening an existing directory leaves native edits intact; capture reads only the selection, overlays active buffers, persists the current copy and retains the remote base. Deleted selected folders become deletions, while a missing previously installed workspace reports a missing-copy condition instead of resurrecting old documents. An installation marker distinguishes that case from an interrupted initial installation that can safely finish from its archive.

Temporary stage names include the copy identity. Cleanup removes that copy's working files and interrupted stages before dropping ownership metadata; unrelated cache entries and outside symlink targets are preserved. Six adapter tests cover actual file/archive reopening, native edits, creation/deletion, captured buffers, bounds/tampering/permissions, initial interruption, missing-directory protection, stage cleanup and symlink guards. These are filesystem/use-case boundaries; native editor draft recovery, peer enrollment/client UI, revocation-driven closing of open documents and atomic remote reconciliation still require application integration.

Snapshot validation now rejects a file path that is also an ancestor directory, including case/Unicode aliases. [#102](https://github.com/PinedaTec-EU/LeonardoMD/issues/102) records the reproduced failure and atomic-write regression; the fix remains in the draft until main integration. Latest full validation passes 195 XCTest cases (six optional cases skipped) plus 12 renderer tests, and the iOS Simulator target builds.


## Desktop peer client checkpoint

`DesktopPeerLibrary` owns enrollment, authorized project import, offline opening and comparison through transport, credential, metadata and workspace ports. Each connection has an independent local credential identity, so a server-issued device ID cannot replace another connection's secret. Connection archives use bounded private atomic writes and contain no credentials. Import records ownership before installation so interrupted copies remain cleanup targets. Capturing offline disk edits and buffers precedes remote comparison; an unreachable server retains that captured work without advancing the base.

Authorization denial is persisted before cleanup. The access-revocation port closes affected copies before removing their files; failed cleanup keeps the durable denial and ownership for a later retry, including without a network connection. The native editor implementation of that port is still pending. Four use-case tests cover enrollment/import, offline comparison failure, separate credential identities and revocation retries; one uses the actual pinned loopback HTTPS service for manual pairing, consent, scoped import and revocation. This is backend acceptance, not a physical two-Mac or native editor reconciliation acceptance. The full suite passes 199 XCTest cases (six optional skips) plus 12 renderer tests.


## Native desktop peer integration checkpoint

Preferences now include Linked Macs with HTTPS/IP:port or pairing-link enrollment, independent cross-code display, authorized project import, local offline opening and three-way base/local/remote comparison. The service can export its one-use pairing link for another Mac and uses device-neutral consent wording. The application controller owns a dedicated credential namespace and keeps transport/cache operations behind the library port. A per-installation interval supports manual, 1, 5, 15, 30 or 60 minute synchronization; periodic work obtains authorization and comparisons without automatically applying or discarding changes.

The application wires the access-revocation port across every document window. Affected sessions stop, clear document/project/content/preview state, cancel scheduled saves and disappear from tabs; existing I/O settles before the library deletes their working directories. Unrelated sibling paths and their drafts remain open. A blank active tab remains valid when every affected tab closes. Native tests cover selective draft removal, pending-operation fencing and no autosave after stop. Controller tests cover an empty startup without cache/TLS/network provisioning and persisted interval validation. Inspected optional hosting captures cover the empty preferences state in English and Spanish; they do not prove a fresh packaged process or physical peer acceptance.

Full validation passes 204 XCTest cases (seven optional skips) plus 12 renderer tests. Native scope enforcement for recent/external opens and file operations, decision editing/application, authenticated remote proposals/receipts, VPN policy and two-Mac end-to-end acceptance remain pending. The comparison screen currently reads differences; it cannot apply a reconciliation yet.


## Native peer document access checkpoint

A shared native path policy identifies managed copy roots and obtains the current cached authorization before document/project opening and document save/copy/create/rename/move/delete operations. Recent/external opens use the same entry points. Selected individual documents permit their exact paths; ancestor navigation does not grant directory mutation or sibling creation. Folder mutation requires a selected folder grant. Untrusted symlink components, including dangling links, are rejected before document access. Native grant errors use localized messages.

Already running file operations are counted until completion; revocation waits for that count as well as saves, project and Git work before deleting the workspace. Stopped callbacks cannot start another mutation. Three policy tests cover folder/document permissions, denied external opens, dangling aliases and a denied save that preserves both disk content and the draft. Latest full validation passes 207 XCTest cases (seven optional skips) plus 12 renderer tests. Tree/search filtering and workspace-manager actions still require integration of the policy; remote reconciliation/application and full native peer acceptance remain incomplete.
