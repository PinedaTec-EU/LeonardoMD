# On-demand synchronization

Implementation tracked by [#384](https://github.com/PinedaTec-EU/LeonardoMD/issues/384), [PR #385](https://github.com/PinedaTec-EU/LeonardoMD/pull/385).

- `RemoteProjectCatalogue` carries validated paths, folders, lengths and per-file content identities, never file bytes. Authenticated `/catalogue` and `/file` routes preserve project grants, scope, pinned TLS and post-await revocation checks. `ProjectCorpusReader+Catalogue` hashes one saved file at a time without the aggregate snapshot cap.
- `OnDemandCache` owns only read-only remote copies: a persistent global temporary LRU budget (256 MiB initially) and separately accounted offline retention rules. Folder rules cover future descendants; child exclusions are explicit. Document image dependencies inherit retention. Atomic index commits precede blob reclamation; stale retained bytes survive failed updates.
- `DownloadLibrary` is the shared observable boundary; denied projects invalidate in-flight downloads. Hosts remain responsible for authorization before exposing a catalogue or fetching bytes.
- `LeonardoSyncUI` supplies cache settings, contextual retention controls and read-only previews to Mac and iOS. Desktop editable working copies, proposal outboxes and mobile rubric drafts remain outside this cache. **Create editable copy** explicitly materializes a complete editable project.
- New installations refresh every minute while active; existing interval settings remain honored. iOS refreshes on foreground activation and retries retained downloads during refresh. Suspension is not a continuous background listener.
- Guide v24 advances beyond integrated demo v22 and the separately reserved diagnostic v23; v19 was the earlier checkpoint. [#378](https://github.com/PinedaTec-EU/LeonardoMD/issues/378) tracks concurrent-candidate guide identity collisions: verify actual Help archive content against the candidate bundle; never overwrite personal help copies.

- [#390](https://github.com/PinedaTec-EU/LeonardoMD/issues/390): removing retention from a stale fallback must discard that record before LRU processing; otherwise restart validation rejects a stale unretained revision. The restart regression covers this alongside stale-retained availability.
