# ADR 0002: Reevaluate the mobile Git engine and prefer document synchronization

Date: 2026-10-20
Decision state: Proposed architecture direction; owner acceptance and implementation are separate gates.
Tracking: [#244](https://github.com/PinedaTec-EU/LeonardoMD/issues/244).
Evidence baseline: main `88b70a9bea8c5a256b9390c0c3b8f0ec65ed3cf1`.

## Recommendation

**Simplify the product toward desktop-mediated document editing. Do not treat maintaining a custom Git engine as the default long-term architecture.** Keep the existing engine compatible during evaluation and migration; this ADR neither disables it nor authorizes deleting user data or capabilities.

For an editor whose core value is documents and forms, implementing Git transport and object machinery is a substantial secondary responsibility. Its distinctive benefit here is a narrower one: iOS can publish selected document changes directly to a supported Git remote while the desktop is unavailable, across providers, without transferring unrelated file contents. The repository demonstrates that capability technically, but contains no adoption, operating-cost or demand measurements establishing that its incremental value pays for owning the engine.

The preferred replacement sends scoped document proposals to the paired desktop, which performs manual reconciliation and uses installed Git when the user chooses to commit or publish. It retains offline editing and durable queued changes. **It sacrifices publication while the desktop is unavailable and requires an authorized LAN/private-overlay path to synchronize.** That is a product concession requiring explicit owner acceptance, not an equivalent implementation of the current contract.

If desktop-independent publication remains mandatory, evaluate a provider API adapter first for an explicitly supported provider set. If provider-independent Git transport and strict selective transfer also remain mandatory, retain the current bounded engine until a library proves those requirements. There is no demonstrated drop-in replacement in this reevaluation.

## Why a new ADR is necessary

[ADR 0001](0001-native-macos-and-lazy-extensions.md) records the macOS shell and system Git CLI decision. It remains applicable to desktop Git operations. It does not explain the later mobile engine. The [Little Leonardo record](../mobile/little-leonardo.md) describes implementation checkpoints and acceptance evidence, not an alternatives analysis.

The original [issue #92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92) required server-independent Git access beyond LAN, folder selection before file-content transfer, no full-clone fallback, offline mutation, device branches and manual desktop integration. It explicitly excluded editable direct mobile synchronization and sought to avoid a proprietary editable synchronization engine. Those requirements explain why the implemented solution is complicated; they do not establish that this product scope was economical. The desktop-peer implementation now supplies some editable direct-sync machinery, changing the reuse opportunity since the original decision.

This is a present-day reevaluation. It does not invent historical reasons for rejecting libraries or claim that the lighter alternatives were previously prototyped. Acceptance would supplement ADR 0001 for mobile strategy; changes to the product contract remain a separate decision. Until then, #92 and the implemented behavior remain authoritative.

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

## Requirements to preserve and requirements to reconsider

Preserve selected-content boundaries; explicit authorization; offline add/edit/delete and restart; bounded resource use; durable retries; manual conflict resolution; later-edit preservation; and an exact association between a proposal and its accepted result. Never silently download unrelated blobs, widen grants, discard drafts or claim integration from a moving branch alone.

Reconsider these product choices independently:

1. Must the mobile device publish while the desktop is off or unreachable?
2. Must that work with arbitrary supported Git hosts over both SSH and HTTPS, or is a named provider sufficient?
3. Must published work remain discoverable through Git without the pairing service?
4. Are Git device branches a user requirement, or an implementation of sending document changes?

Selection is a client transfer policy, not a Git-server authorization boundary. A repository credential may permit access beyond the selected folder even when the app requests only selected content. Migration must preserve the actual transfer guarantees without overstating their security scope.

## Alternatives compared

Ratings below are qualitative engineering judgments based on responsibility ownership. They are not measured time, memory, defect rate or financial savings.

| Option | Offline editing | Publish with desktop unavailable | Provider-independent remote access | Strict selected-content transfer to mobile | Ongoing responsibility |
| --- | --- | --- | --- | --- | --- |
| A. Current custom engine | Implemented | Implemented for supported remotes | Git protocol; requires server capabilities | Implemented with filtering and selected wants; unsupported servers fail | Git subset, transports and product reconciliation |
| B. Existing embedded Git library | Feasible; migration needed | Feasible | Candidate-specific; unproven here | Not demonstrated for required filtering | Library integration, security updates and product reconciliation |
| C. Provider Git-object API | Feasible; new adapter needed | Yes for chosen provider, subject to API/auth limits | No | Selected blob reads are feasible; must prove bounds and metadata handling | Provider API/auth plus product reconciliation |
| D. Desktop-mediated editable documents | Existing desktop-peer logic can inform a mobile implementation | No; queue until desktop reachable | Desktop keeps installed Git support | Granted document snapshots; no mobile Git fetch | Direct service, offline proposals, conflicts and receipts |
| E. Direct read-only mobile + explicit file export | Existing reading/offline cache; no integrated editable sync | No integrated publication | Git stays on desktop | Existing granted snapshots | Lowest new sync responsibility; much less product capability |

### A. Maintain the current engine

The strongest case is simultaneous demand for desktop independence, provider independence and selected-only transfer. Existing interoperability evidence includes real Git packs, SHA-1/SHA-256 fixtures, generated-key SSH, offline mutation and two publication/integration cycles; see [validation](../validation/little-leonardo/README.md). These are useful migration oracles, not proof of broad host compatibility, physical-device readiness, low maintenance cost or security completeness. No tests were rerun for this documentation change.

Future cost includes hostile-input parsing, protocol/server compatibility, credentials and host keys, dependency updates, resource limits, interrupted pushes and integration recovery. Supporting a protocol subset does not remove these obligations. Keep this option only for a demonstrated product need or as a compatibility bridge, not because it is already built. Immediate removal would also create avoidable migration and data-loss risk.

### B. Replace the engine with an existing library

A C library such as libgit2 could transfer object/pack/transport maintenance upstream while retaining native integration. The [v1.9.7 fetch options](https://libgit2.org/docs/reference/v1.9.7/remote/git_fetch_options.html) expose shallow depth but no object-filter option. The inspected [main API](https://libgit2.org/docs/reference/main/remote/git_fetch_options.html) has the same relevant limitation. **This is evidence that a straightforward supported fetch configuration is not established; it is not proof that every extension or library is incapable.** A wrapper does not by itself add an absent underlying capability.

Sparse checkout limits the working tree; [partial clone](https://git-scm.com/docs/partial-clone) limits fetched objects. [Sparse-checkout documentation](https://git-scm.com/docs/git-sparse-checkout) therefore does not establish compliance with the mobile transfer contract. A shallow/full fetch followed by deleting unwanted files fails that contract.

Before selection, a bounded spike must prove iOS packaging, required hashes, authentication/host trust, metadata-first folder selection, no excluded blobs, safe publication and interruption recovery against actual supported servers. Assess licensing, dependency footprint and Swift/C ownership too. No library was built or benchmarked in this task. Recreating filtering or transport in a custom fork risks retaining the difficult work while adding an abstraction. B is a sensible feasibility candidate if current product requirements survive; it is not an approved replacement.

### C. Use a provider API

GitHub's [Git database API](https://docs.github.com/en/rest/guides/using-the-rest-api-to-interact-with-your-git-database) supports reading objects, creating blobs/trees/commits and updating references without a local Git installation. A mobile adapter could read metadata, fetch only selected blobs and publish one commit containing all selected edits. Preserve untouched tree entries with an explicit base tree; handle [tree truncation and limits](https://docs.github.com/en/rest/git/trees) rather than treating an incomplete listing as a complete repository. Use checked [reference updates](https://docs.github.com/en/rest/git/refs#update-a-reference), unique publication identity and readback after uncertain outcomes; do not force-update over concurrent work.

This removes mobile pack decoding, Git wire protocol and SSH integration. It retains offline state, optimistic concurrency, conflicts, publication journals and exact integration semantics. It introduces provider authentication, token scopes, API limits and provider/version compatibility. A per-file contents upload loop is not equivalent to an atomic multi-file proposal.

Choose C ahead of a custom protocol engine if independent mobile publication is valuable and a limited provider set is acceptable. GitHub illustrates feasibility; GitLab or other adapters would need separate evidence. No provider API prototype, private-repository authentication flow or performance test was performed here.

### D. Reuse the direct-sync foundation for editable mobile proposals — preferred direction

Download the authorized corpus, edit locally, and persist a proposal containing its identity, base revision, selected scope and changes. Queue it while disconnected. When the paired desktop is reachable, upload it, review explicitly against current files and drafts, apply through the transaction journal, and return an immutable receipt. Incorporate that receipt without discarding edits made after submission. Desktop Git commit/push remains an explicit desktop workflow with a separate success/failure state.

[DesktopPeerCopy](../../Sources/LeonardoSync/DesktopPeerCopy.swift), [DesktopPeerProposal](../../Sources/LeonardoSync/DesktopPeerProposal.swift), [DesktopPeerAcceptance](../../Sources/LeonardoDesktopSync/DesktopPeerAcceptance.swift) and the transaction/receipt stores provide reuse candidates. Mobile direct mode currently remains read-only. The existing desktop-peer path does not prove mobile permission handling, lifecycle recovery, UI or migration readiness. Editable mobile grants, revocation, eventual cache deletion and queued-proposal behavior must be designed and tested explicitly; do not silently grant write permission to existing read-only pairings.

This contradicts #92's original exclusion of proprietary editable mobile synchronization. It is preferable now only because a scoped reconciliation foundation already exists for desktop peers and because we recommend relaxing desktop-independent publication. It still owns a synchronization protocol. Building a second parallel conflict engine would defeat the simplification: reuse common state/receipt boundaries and measure the net reduction before removing Git.

No public Internet relay or cloud backend is proposed. The Mac must be running and reachable over the authorized private network/overlay to receive changes. “Saved locally”, “received by desktop”, “applied”, and “published to Git” must remain distinguishable. This option loses Git-only discovery of pending mobile branches; the direct inbox becomes the discovery mechanism. It cannot be sold as equivalent remote availability.

### E. Reduce scope to reading and explicit file exchange

Keep direct cached reading and let users export edited documents for manual import on desktop, or keep mobile entirely read-only. This removes the most synchronization work, but loses integrated multi-file sends, deletion semantics, durable acknowledgements and conflict continuity. Export is a useful recovery path, not an equivalent editing workflow. Prefer E only if mobile editing is not a product priority; it gives up more value than D.

## Does maintaining the engine pay?

**Long term: the evidence does not justify custom Git as the default investment; prefer D. Short term: retaining compatibility is safer than an immediate rewrite or removal.** C is the fallback direction if independent publication is essential and provider scope can narrow. A remains justified if the owner explicitly retains all three demanding requirements and B cannot satisfy them with lower ownership cost.

Past implementation effort is sunk cost. Existing verified behavior matters because replacing it creates future migration and regression work. Both must be considered without confusing them.

A cost comparison must include:

- **Keep:** expected Git-specific maintenance/security/interoperability work, dependency support and opportunity cost over a stated planning horizon.
- **Simplify:** implementation and data migration, temporary dual support, direct-sync maintenance, retained conflict/receipt work and the user cost of waiting for the desktop.
- **Value lost:** how often users actually need direct publication while the desktop is unavailable, and whether provider restrictions are acceptable.

There are no measured values for these terms in the repository evidence inspected. Do not invent person-week estimates or claim quantified savings from line counts. Before a migration commitment, record an owner-reviewed estimate for the same horizon and an explicit account of the lost workflow. If D creates comparable custom machinery without removing Git responsibilities, reject that migration rather than running both indefinitely.

## Staged decision and migration gates

1. **Accept or reject the product concession.** Record the owner's choice on desktop availability, supported providers and Git-only discovery. This ADR proposes a direction; it does not amend #92 or authorize a runtime migration by itself.
2. **Prove one replacement path.** For D, reuse the existing direct proposal/receipt core in a bounded iOS vertical slice. If desktop independence is retained, spike C or B according to the required provider scope. Do not implement all alternatives.
3. **Compare net ownership.** List modules/dependencies actually removed, logic retained, new code owned, estimated transition effort and ongoing maintenance. Establish acceptance of the user workflow with a reachable and an unavailable desktop. No retirement approval without this comparison.
4. **Preserve in-flight work.** Inventory Git connections, base/current/published snapshots, device branches, pending receipts and credentials. Provide an export/recovery path. Either complete each pending Git cycle through the old adapter or migrate it with a verified exact baseline; never relabel an unintegrated send as applied. Migration must be idempotent across restart, avoid duplicate sends and preserve later local edits.
5. **Validate and stage retirement.** Prove add/edit/delete, conflicts with unsaved desktop buffers, scope exclusions, failed delivery, restart before/after acceptance, repeated receipts, revocation and later edits. For any remote replacement, prove no unrelated blob transfer against real servers. Retain a compatibility reader/adapter until pending state is drained; remove only unused code after a separately reviewed migration. Rollback must preserve the original state and exportable edits, without dual-publishing proposals.

Owner acceptance of the direction, prototype success and implementation delivery are distinct events. This documentation-only PR completes the reevaluation, not those events. Runtime/source migration requires its own canonical issue, product-contract update, current-head tests, CI and independent review.

## Revisit conditions and evidence limits

Revisit this recommendation when actual usage demonstrates desktop-independent, provider-independent publication is important; a maintained library proves strict selective transfer; or measured transition cost outweighs expected future Git ownership over the chosen horizon. Conversely, recurring Git-only compatibility/security work strengthens the case for simplifying but must be evidenced, not presumed.

Repository evidence was inspected locally at the baseline above; historical validation is linked rather than newly claimed. External sources are official Git, libgit2 and GitHub documentation retrieved through the web tool's HTML/text representation on 2026-10-20. These establish API capabilities and distinctions, not comparative performance or customer demand. No provider benchmark, library spike, physical-device test or migration was performed. Human-versus-agent representations were not compared; no source instructions were used as operational instructions.

For future decisions to own a standard protocol, record the user benefit, lighter alternatives, verified capability gaps, ongoing ownership and exit conditions before implementation. This consolidates the missing decision evidence exposed here rather than adding a blanket ban on custom components.
