# ADR 0002: Reevaluate the mobile Git engine and prefer document synchronization

Date: 2026-10-20
Decision state: Owner-selected product direction on 2026-10-20; runtime migration and Windows delivery remain pending.
Tracking: [#244](https://github.com/PinedaTec-EU/LeonardoMD/issues/244).
Evidence baseline: main `88b70a9bea8c5a256b9390c0c3b8f0ec65ed3cf1`.

## Decision

**Simplify: iOS is a read-only companion; editable document synchronization belongs between LeonardoMD desktop instances on macOS and Windows. Retire the custom mobile Git engine through a separately validated migration.** The owner selected this direction on 2026-10-20 after the first reevaluation draft.

The target contract is:

- **iOS:** read authorized documents/resources, refresh them from a paired desktop, and retain an offline reading cache. No document creation, editing, form-value mutation, deletion, editable proposal submission, Git enrollment or Git publication. Read-only is an authorization boundary as well as a UI constraint; preferences and owned cache maintenance remain possible.
- **macOS/Windows:** create and edit local documents offline, synchronize explicitly selected documents/folders between desktop peers, and reconcile conflicts manually without discarding unsaved work. Peer synchronization must not require Git or a cloud backend. Git remains an optional independent desktop workflow using an established implementation; synchronization success does not imply a Git commit or push.
- **Connectivity:** retain authenticated, explicitly authorized LAN/private-overlay synchronization. A peer must be running and reachable to exchange changes; existing local copies remain usable offline. There is no promise of continuous background execution, public Internet relay or always-available cloud synchronization.

This replaces the first draft's suggestion of editable iOS proposals. It also deliberately gives up the original mobile requirements for offline editing and publication to a Git host while the desktop is unavailable. Those are accepted product reductions, not implementation equivalence.

For a document/form editor, owning Git framing, packs and remote publication no longer provides a needed mobile capability under this contract. **Long-term maintenance of the custom mobile engine does not compensate for its benefits in the selected product scope.** Keep compatibility temporarily to recover pending work; do not expand it into a general Git client or replace it with a provider API or another mobile Git library.

This ADR records the selected direction and retirement gates. It does not remove current runtime capabilities, implement Windows, or authorize discarding in-flight work. Windows is currently roadmap work under [#227](https://github.com/PinedaTec-EU/LeonardoMD/issues/227); selecting desktop sync does not claim that a Windows edition or a portable sync service exists.

## Why a new ADR is necessary

[ADR 0001](0001-native-macos-and-lazy-extensions.md) records the macOS shell and system Git CLI decision. It remains applicable to desktop Git operations. It does not explain the later mobile engine. The [Little Leonardo record](../mobile/little-leonardo.md) describes implementation checkpoints and acceptance evidence, not an alternatives analysis.

The original [issue #92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92) required server-independent Git access beyond LAN, folder selection before file-content transfer, no full-clone fallback, offline mutation, device branches and manual desktop integration. It explicitly excluded editable direct mobile synchronization and sought to avoid a proprietary editable synchronization engine. Those requirements explain why the implemented solution is complicated; they do not establish that this product scope was economical. The desktop-peer implementation now supplies some editable direct-sync machinery, changing the reuse opportunity since the original decision.

This is a present-day reevaluation. It does not invent historical reasons for rejecting libraries or claim that the lighter alternatives were previously prototyped. The owner-selected direction supplements ADR 0001 for mobile/desktop synchronization strategy and supersedes the mobile editing/Git requirements in #92 for the future product. #92 and the checkpoints remain evidence of historical requirements and implemented behavior until migration delivers the new contract.

## What we actually own

At the baseline, `Sources/LeonardoGit` contains **43 Swift files / 4,092 lines**, and `Tests/LeonardoGitTests` contains **16 Swift files / 4,719 lines**. Counts include blank lines/comments and exclude app integration, mobile UI, shared sync, dependencies and other tests. Reproduce by counting `*.swift` files and `splitlines()` in those two directories. The earlier informal count of 42 production files was incorrect. These are scope indicators, not development-time or defect estimates.

| Responsibility | Evidence | What replacement can remove |
| --- | --- | --- |
| Git wire negotiation, framing and fetch/push replies | `GitPacket`, `GitV2Capabilities`, `GitFetchResponse`, `GitPushReport` | Library, provider API or desktop mediation can remove mobile ownership, subject to feasibility |
| Packs, delta reconstruction, object identity and commit/tree construction | `GitPack`, `GitDelta`, `GitObjectWriter`, `GitTreePatch`, `GitCommitBuilder` | Provider API or desktop Git can own Git representation; a library can own much of it |
| HTTPS Git and SSH integration | `GitHTTPTransport`, `GitSSHTransport`, `GitSSHKeys`, `GitSSHHostKeyStore` | API removes mobile SSH; mediation removes mobile remote credentials and Git transport |
| Durable publication, retry and exact integration baseline | `GitPreparedPublication`, `GitPublicationStore`, `GitIntegrationConsumer` | Representation can change; the protection against losing or resending edits must remain |
| Corpus boundaries, offline edits, conflicts and receipts | `LeonardoSync`, `LeonardoDesktopSync`, app coordinators | Mostly retained for any editable synchronization solution |

We have implemented a restricted Git client, not a complete replacement for Git. SSH protocol/authentication primitives come from SwiftNIO SSH; compression uses system zlib. We still own their integration, limits, lifecycle and host-key policy. [Package.swift](../../Package.swift) also pins NIO, transport services and Swift Crypto. Dependency removal must follow a usage audit, not an assumption that every dependency belongs exclusively to Git.

Desktop already uses installed Git through [GitRepository](../../Sources/LeonardoCore/GitRepository.swift) and [DesktopGitCLIAdapter](../../Sources/LeonardoApp/DesktopGitCLIAdapter.swift). The custom module is also imported by desktop integration, so retiring mobile transport does not immediately make the whole target deletable.

## Requirements retained and deliberately removed

Preserve selected-content boundaries; explicit authorization; offline add/edit/delete and restart; bounded resource use; durable retries; manual conflict resolution; later-edit preservation; and an exact association between a proposal and its accepted result. Never silently download unrelated blobs, widen grants, discard drafts or claim integration from a moving branch alone.

The owner has removed mobile editing, mobile Git publication, provider-independent mobile transport and Git-only discovery of mobile proposals from the target product. Device branches and mobile integration receipts are legacy state to drain, not features to rebuild. iOS refreshes only its approved reading cache; it must not hold an editable desktop-peer grant.

Editable desktop peers retain durable offline work, proposal identity, base/current/incoming comparison and exact receipts. These responsibilities remain even when Git transport disappears. Scope selection governs both document transfer and desktop mutation.

Selection is a client transfer policy, not a Git-server authorization boundary. A repository credential may permit access beyond the selected folder even when the app requests only selected content. Migration must preserve the actual transfer guarantees without overstating their security scope.

## Alternatives compared

Ratings below are qualitative engineering judgments based on responsibility ownership. They are not measured time, memory, defect rate or financial savings. A–C compare the historical editable-mobile contract; D is the selected reduced mobile/desktop contract.

| Option | Offline editing | Publish with desktop unavailable | Provider-independent remote access | Strict selected-content transfer to mobile | Ongoing responsibility |
| --- | --- | --- | --- | --- | --- |
| A. Current custom engine | Implemented | Implemented for supported remotes | Git protocol; requires server capabilities | Implemented with filtering and selected wants; unsupported servers fail | Git subset, transports and product reconciliation |
| B. Existing embedded Git library | Feasible; migration needed | Feasible | Candidate-specific; unproven here | Not demonstrated for required filtering | Library integration, security updates and product reconciliation |
| C. Provider Git-object API | Feasible; new adapter needed | Yes for chosen provider, subject to API/auth limits | No | Selected blob reads are feasible; must prove bounds and metadata handling | Provider API/auth plus product reconciliation |
| D. Read-only iOS + editable macOS/Windows peers | Desktop only; iOS caches reading | No mobile publication; desktops queue sync while peers are offline | Sync is independent of Git providers | Granted reading snapshots; no mobile Git fetch | Direct service and desktop reconciliation; Windows adapters pending |
| E. Read-only iOS + manual desktop exchange | Desktop local editing only | No integrated mobile publication | Git stays on desktop | Existing granted snapshots | Lowest sync responsibility; loses desktop reconciliation |

### A. Maintain the current engine

The strongest case is simultaneous demand for desktop independence, provider independence and selected-only transfer. Existing interoperability evidence includes real Git packs, SHA-1/SHA-256 fixtures, generated-key SSH, offline mutation and two publication/integration cycles; see [validation](../validation/little-leonardo/README.md). These are useful migration oracles, not proof of broad host compatibility, physical-device readiness, low maintenance cost or security completeness. No tests were rerun for this documentation change.

Future cost includes hostile-input parsing, protocol/server compatibility, credentials and host keys, dependency updates, resource limits, interrupted pushes and integration recovery. Supporting a protocol subset does not remove these obligations. Under the selected scope keep this option only as a compatibility bridge; a new product decision would be needed to retain mobile Git long term. Immediate removal would also create avoidable migration and data-loss risk.

### B. Replace the engine with an existing library

A C library such as libgit2 could transfer object/pack/transport maintenance upstream while retaining native integration. The [v1.9.7 fetch options](https://libgit2.org/docs/reference/v1.9.7/remote/git_fetch_options.html) expose shallow depth but no object-filter option. The inspected [main API](https://libgit2.org/docs/reference/main/remote/git_fetch_options.html) has the same relevant limitation. **This is evidence that a straightforward supported fetch configuration is not established; it is not proof that every extension or library is incapable.** A wrapper does not by itself add an absent underlying capability.

Sparse checkout limits the working tree; [partial clone](https://git-scm.com/docs/partial-clone) limits fetched objects. [Sparse-checkout documentation](https://git-scm.com/docs/git-sparse-checkout) therefore does not establish compliance with the mobile transfer contract. A shallow/full fetch followed by deleting unwanted files fails that contract.

Before selection, a bounded spike must prove iOS packaging, required hashes, authentication/host trust, metadata-first folder selection, no excluded blobs, safe publication and interruption recovery against actual supported servers. Assess licensing, dependency footprint and Swift/C ownership too. No library was built or benchmarked in this task. Recreating filtering or transport in a custom fork risks retaining the difficult work while adding an abstraction. B would be a feasibility candidate only if the historical editable-mobile requirements were reintroduced. Under the selected read-only scope it is unnecessary.

### C. Use a provider API

GitHub's [Git database API](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-your-git-database) supports reading objects, creating blobs/trees/commits and updating references without a local Git installation. A mobile adapter could read metadata, fetch only selected blobs and publish one commit containing all selected edits. Preserve untouched tree entries with an explicit base tree; handle [tree truncation and limits](https://docs.github.com/en/rest/git/trees) rather than treating an incomplete listing as a complete repository. Use checked [reference updates](https://docs.github.com/en/rest/git/refs#update-a-reference), unique publication identity and readback after uncertain outcomes; do not force-update over concurrent work.

This removes mobile pack decoding, Git wire protocol and SSH integration. It retains offline state, optimistic concurrency, conflicts, publication journals and exact integration semantics. It introduces provider authentication, token scopes, API limits and provider/version compatibility. A per-file contents upload loop is not equivalent to an atomic multi-file proposal.

C could be preferable to a custom protocol engine if a future decision reintroduced independent mobile publication with a limited provider set. It is unnecessary for the selected read-only scope. GitHub illustrates feasibility; GitLab or other adapters would need separate evidence. No provider API prototype, private-repository authentication flow or performance test was performed here.

### D. Read-only iOS and editable desktop peers — selected direction

iOS receives only authorized document snapshots and resources. It keeps offline reading, manual/foreground refresh and eventual revocation cleanup. Creating or editing documents and filling/saving forms belong to desktop applications. Hiding edit controls is insufficient: the client must not enroll as a desktop peer or invoke mutation routes.

Desktop instances retain editable scoped copies. A change proposal identifies its base revision and scope; the receiving desktop reviews it against current files and unsaved buffers, applies an approved result through a recoverable transaction, and returns an immutable receipt. Later local edits survive incorporation. Existing [DesktopPeerCopy](../../Sources/LeonardoSync/DesktopPeerCopy.swift), [DesktopPeerProposal](../../Sources/LeonardoSync/DesktopPeerProposal.swift), [DesktopPeerAcceptance](../../Sources/LeonardoDesktopSync/DesktopPeerAcceptance.swift), journals and receipt stores provide a macOS reference implementation. [PairingRegistry](../../Sources/LeonardoSync/PairingRegistry.swift) already distinguishes `readOnly` and `desktopPeer` grants.

This reuses the existing editable desktop model rather than inventing another reconciliation engine for mobile. It removes the need for mobile Git remote credentials, packs, object publication and Git-only proposal discovery. It still owns a bounded synchronization protocol, secure pairing, retries and conflict handling; simplification is not the elimination of all distributed-state complexity.

#### macOS/Windows interoperability contract

The Windows issue originally excluded synchronization from its initial local-document scope. The owner's new direction adds cross-desktop sync as a future product workstream; it does not silently turn that deferred Windows edition into an immediate implementation commitment or require it to ship with sync on day one.

Portable contracts and conformance fixtures should be the reuse boundary, not an assumed shared Apple runtime. `LeonardoSync/PairingRegistry.swift` imports Security/CryptoKit; `LeonardoSyncTransport/LANHTTPSListener.swift` uses Network.framework; desktop runtime, identity and filesystem adapters are macOS-gated. Windows needs its own secure credential/certificate storage, TLS/networking, filesystem and application-buffer adapters. Their feasibility has not been proven in this task.

Before implementation, specify and test:

1. A versioned document-snapshot/proposal/receipt protocol, explicit capability negotiation, compatible schema evolution, and fail-closed handling of unsupported clients. Both platforms can serve or consume an explicitly granted project; one designated source owner per shared project coordinates manual acceptance. This is not unrestricted multi-master replication. Changing the source owner requires a separate migration contract.
2. Identical MDLF/MDLR/MDLZ semantics and byte preservation where appropriate; one proposal must not expose half of a packaged document. Treat package files as atomic transfer units unless a separately agreed package-aware merge exists.
3. A portable relative-path policy covering case and Unicode aliases, Windows reserved names, separators, symlinks/reparse points and traversal. Reject incompatible/conflicting names before materialization; never silently rename or omit content and call synchronization complete.
4. Base/current/incoming conflict review for concurrent edits, additions and deletions; stale-review rejection; unsaved-buffer leases; bounded recoverable transactions; exact receipt incorporation; durable retries and duplicate suppression across restart. Do not assume atomic multi-file filesystem operations are equivalent on both operating systems.
5. Consent-bound read-only versus desktop-peer roles, host identity verification, device-local secret storage, explicit project grants and revocation on both platforms. A read-only iOS credential cannot be upgraded implicitly. A binary claiming to be a desktop is not proof of permission; explicit owner consent authorizes a write-capable peer.
6. Real macOS↔Windows conformance and end-to-end evidence for pairing, selected-only transfer, offline reconnect, conflicts, interruption recovery, revocation and mixed protocol versions, plus same-platform regression checks. macOS fixtures alone do not establish Windows acceptance.

Retain the existing LAN/private-overlay boundary for the first scope. No new public service, relay or mandatory Git repository is introduced. Show locally saved, submitted, accepted and synchronized as distinct states; any subsequent Git commit/push has its own status.

### E. Read-only mobile with no editable desktop synchronization

Keeping iOS reading while using only explicit document export/manual copy on desktops has the lowest synchronization responsibility. It loses integrated desktop offline reconciliation, deletion continuity and durable acknowledgements. Export remains useful for recovery, but E does not meet the selected desktop synchronization goal. D is therefore preferred even though E would remove more code.

## Does maintaining the engine pay?

**For the selected scope, no: a read-only iOS reader and document synchronization between desktops do not require a proprietary Git client.** Historical Git interoperability tests remain valuable for safely draining legacy work, not a reason to preserve unnecessary mobile publication indefinitely. A library or provider API would retain an unwanted mobile capability and add migration work without solving a current target requirement.

The original engine was motivated by the simultaneous requirements for mobile editing, desktop-independent publication and provider-independent selected-only Git transfer. The owner has now removed those requirements. This is the concrete reason the cost/benefit decision changes; the conclusion does not depend on a fabricated performance or financial estimate.

Existing verified behavior matters because replacing it creates future migration and regression work. Do not confuse that transition cost with a reason for indefinite expansion. Retirement still needs a module/dependency usage audit: desktop code imports `LeonardoGit`, and not all NIO/Crypto/zlib usage can be assumed removable. Preserve normal desktop Git CLI integration and unrelated document services.

No measured maintenance hours, adoption data or migration estimate are available in the inspected evidence. Before scheduling implementation, estimate retirement, compatibility support, Windows adapters and ongoing direct-sync ownership over the same planning horizon. Reject a design that keeps both full Git and a second redundant reconciliation engine indefinitely. Do not promise a line-count reduction or delivery date from this ADR alone.

## Staged implementation and migration gates

1. **Record the product decision — completed in this ADR.** iOS read-only; editable sync between macOS/Windows; no mobile Git replacement. Track runtime retirement and Windows sync implementation separately with canonical issues and acceptance criteria. Documentation acceptance does not establish runtime delivery.
2. **Protect legacy edits before disabling writes.** Inventory mobile Git connections, base/current/published snapshots, branches, pending receipts and credentials. Provide recovery/export to a desktop. Drain already published proposals with the compatibility adapter or migrate them with a verified exact baseline. Never relabel pending work as applied, delete unsent content, or publish it automatically as part of an upgrade. The reader-only UI may offer recovery of legacy work without creating new edits.
3. **Deliver iOS read-only enforcement.** Remove new Git enrollment and document mutation flows; prohibit writable peer enrollment and proposal submission; retain only authorized reading/refresh/cache behavior. Existing paired desktops must explicitly downgrade or revoke obsolete writable grants; already issued credentials cannot be made read-only by hiding controls. Preserve historical Git branches independently of direct-cache revocation.
4. **Specify and prove desktop interoperability.** Build a bounded macOS/Windows vertical slice using the protocol contract above. Preserve the Windows local-document roadmap as a prerequisite, without claiming portability from shared Swift module names. Test the same fixtures on both platforms and an actual cross-platform exchange before broad rollout.
5. **Retire only unused Git responsibilities.** Audit app/mobile dependencies and serialized data, retain compatibility needed to drain old proposals, then remove obsolete Git transport/object/publication code in a separately reviewed change. Prove desktop Git commands and desktop sync still work independently. Preserve versioned legacy archives until recovery is verified.
6. **Validate migration and rollback.** Prove restart at each state transition, repeated receipts, no duplicate publication, later-edit preservation and recovery from a failed upgrade. Test iOS reading online/offline and mutation denial, and desktop edit/create/delete/conflict flows. Rollback must preserve recoverable user work without re-enabling stale credentials or dual-submitting proposals.

The documentation PR completes the reevaluation and records owner selection. Runtime/source migration, permission changes and Windows work require their own issue-linked changes, current-head validation, CI and independent review. No runtime behavior changes in this PR.

## Revisit conditions and evidence limits

Reopen the decision if the owner reintroduces mobile editing or remote Git publication, or if cross-platform implementation evidence changes the desktop design. New mobile Git demand would require a new alternatives analysis; it must not silently reactivate the retired architecture. Measured maintenance and migration evidence should guide sequencing without changing the selected read-only mobile contract by accident.

Repository evidence was inspected locally at the baseline above; historical validation is linked rather than newly claimed. External sources are official Git, libgit2 and GitHub documentation retrieved through the web tool's HTML/text representation on 2026-10-20. These establish API capabilities and distinctions, not comparative performance or customer demand. No provider benchmark, library spike, physical-device test or migration was performed. Human-versus-agent representations were not compared; no source instructions were used as operational instructions.

For future decisions to own a standard protocol, record the user benefit, lighter alternatives, verified capability gaps, ongoing ownership and exit conditions before implementation. This consolidates the missing decision evidence exposed here rather than adding a blanket ban on custom components.
