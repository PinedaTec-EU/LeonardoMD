# On-demand synchronization

Implementation tracked by [#384](https://github.com/PinedaTec-EU/LeonardoMD/issues/384), [PR #385](https://github.com/PinedaTec-EU/LeonardoMD/pull/385).

- `RemoteProjectCatalogue` carries validated paths, folders, lengths and per-file content identities, never file bytes. Authenticated `/catalogue` and `/file` routes preserve project grants, scope, pinned TLS and post-await revocation checks. `ProjectCorpusReader+Catalogue` hashes one saved file at a time without the aggregate snapshot cap.
- `OnDemandCache` owns only read-only remote copies: a persistent global temporary LRU budget (256 MiB initially) and separately accounted offline retention rules. Folder rules cover future descendants; child exclusions are explicit. Document image dependencies inherit retention. Atomic index commits precede blob reclamation; stale retained bytes survive failed updates.
- `DownloadLibrary` is the shared observable boundary; denied projects invalidate in-flight downloads. Hosts remain responsible for authorization before exposing a catalogue or fetching bytes.
- `LeonardoSyncUI` supplies cache settings, contextual retention controls and read-only previews to Mac and iOS. Desktop editable working copies, proposal outboxes and mobile rubric drafts remain outside this cache. **Create editable copy** explicitly materializes a complete editable project.
- New installations refresh every minute while active; existing interval settings remain honored. iOS refreshes on foreground activation and retries retained downloads during refresh. Suspension is not a continuous background listener.
- Guide27 adds explicit cache-limit application to accepted Classic Guide25, diagnostic Guide23 and the on-demand guidance; v19 was the initial checkpoint. [#378](https://github.com/PinedaTec-EU/LeonardoMD/issues/378) tracks concurrent-candidate guide identity collisions: verify actual Help archive content against the candidate bundle; never overwrite personal help copies.

- [#390](https://github.com/PinedaTec-EU/LeonardoMD/issues/390): removing retention from a stale fallback must discard that record before LRU processing; otherwise restart validation rejects a stale unretained revision. The restart regression covers this alongside stale-retained availability.

- [#391](https://github.com/PinedaTec-EU/LeonardoMD/issues/391): after a cache mutation, refresh all authorized observable project snapshots; global LRU eviction can remove another project’s temporary file. A two-project constrained-budget regression verifies both the real index and the visible downloaded flags.

- [#395](https://github.com/PinedaTec-EU/LeonardoMD/issues/395): every open path must recheck the original authorization generation and cancellation immediately before returning bytes, including after the final cache refresh, shared tasks and stale fallback reads. A persistence port allows deterministic suspension of actual cache completions; both late-refresh and stale-fallback regressions failed before correction. Usage refreshes discard superseded replies after revocation.

- [#396](https://github.com/PinedaTec-EU/LeonardoMD/issues/396): the cache-limit field keeps an independent text draft and a visible MiB label; Apply/Return commits a validated whole number once. Background usage replies cannot rewrite an active edit. Guide27 documents the explicit action and preserves existing personal Guide26 copies. Native iOS keyboard replacement reproduced256128 instead of128 before correction.

- Reauthorization is generation-scoped in both task deduplication and deferred cleanup. A deterministic store-completion regression for #395 verifies that an old grant cannot join or delete a newly retained revision. Purge remains the host revocation operation.

Revocation immediately detaches/cancels that project's active downloads and clears
only its published progress/failures. Cancelled work may finish later; its obsolete
generation cannot alter a new grant, including a cached reopen. The deterministic
#395 regressions cover both held completion and preservation of other projects' errors.

Remote presentation is keyed by project, path, catalogue and a per-load generation. Revision changes hide old text/images before the replacement task starts; failed replacement and obsolete success/error completions cannot restore prior presentation. Regression [#402](https://github.com/PinedaTec-EU/LeonardoMD/issues/402) includes same-catalogue retry and cross-document/project isolation.

Retained fallback freshness is explicit in `RemoteDownloadResult`: the preview receives
the old file and its failed-update reason atomically. It renders a previous-copy
warning and Retry above readable content; referenced-image failures are also
visible above the document. Native integration checks mount the production preview
with the real download library and disk cache, retain A, advertise B and fail B.
Both locales must show A, the warning, original error and Retry. This supplements
the generation-state tests that alone missed the service fallback in
[#402](https://github.com/PinedaTec-EU/LeonardoMD/issues/402). Guide32 preserves
the accepted connection/rubric help while adding this recovery policy.

Transfers are keyed by authorization, exact catalogue entry and a per-transfer UUID.
A newer revision starts independently, cancels the obsolete transfer and keeps its
own progress/error state. Every completion checks the current catalogue before
returning bytes or publishing failures. The real-cache held-fetch regression for
[#402](https://github.com/PinedaTec-EU/LeonardoMD/issues/402) failed four assertions
before correction. Hosted preview acceptance separates native warning OCR from
actual WKWebView DOM readiness/visible heading geometry; author-owned images
still require readable composited pixels under
[#406](https://github.com/PinedaTec-EU/LeonardoMD/issues/406).
