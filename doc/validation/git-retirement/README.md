# Native Git retirement evidence

Tracking: [#249](https://github.com/PinedaTec-EU/LeonardoMD/issues/249), [PR #250](https://github.com/PinedaTec-EU/LeonardoMD/pull/250).

The captures use synthetic documents and generated local identities. They show the actual SwiftUI/WebKit interfaces. Runtime/mobile source fingerprints and capture checkpoint are retained in [provenance.json](provenance.json); verify those hashes against the reviewed head. Later documentation, evidence or ledger changes do not imply different runtime pixels.

## Verified behavior

- Final full-suite confirmation: 432 XCTest cases (20 optional fixture/capture skips) and 28 Swift Testing cases, zero failures. The latest compiler-bearing full run includes the recovery-ownership regressions for [#251](https://github.com/PinedaTec-EU/LeonardoMD/issues/251); the optional component-capture case passed separately. Focused corpus recovery, removed route, desktop copy and system Git checks also pass. The ownership regression was observed failing before the store fix and now passes with byte-for-byte archive preservation.
- The compilation recorder suite passes 7 tests; the complete scripts suite passes 32 tests with 7 environment-dependent ledger skips. Successful compiler invocations are accumulated in the source PR's ledger entry; failures and test-without-building commands are excluded.
- Signed iOS Simulator build-for-testing succeeds. Five native UI tests pass: cached links, rendered Markdown/image/table, legacy JSON export and read-only preview, Git-free settings, and manual pairing controls. The exported file was opened from the task-owned simulator filesystem and its distinct base/current/published content verified.
- Native component capture of system Git and direct-sync settings passes in English and Spanish. Core Git tests exercise actual local bare-remote fetch/pull/push, staged state and conflict handling. Native desktop peer tests exercise actual pinned HTTPS, offline editing and manual receipt-based reconciliation.

Native direct acceptance passes independently: real pinned HTTPS enrollment, desktop consent for a read-only client, refresh, offline retention, service restart/retry and revocation while a document is open. UI and server each exit successfully; simulator-container inspection confirms the revoked corpus/grant is absent and the independent recovery corpus remains. This does not rely on seeded-cache screenshots.

## Captures

| Surface/state | Capture |
| --- | --- |
| System Git controls, Spanish | [system-git-es.png](system-git-es.png) |
| System Git controls, English | [system-git-en.png](system-git-en.png) |
| Direct sync settings, Spanish | [direct-sync-es.png](direct-sync-es.png) |
| Direct sync settings, English | [direct-sync-en.png](direct-sync-en.png) |
| Legacy read-only corpus with recovery export | [ios-recovery-project.png](ios-recovery-project.png) |
| Native JSON file exporter | [ios-recovery-export.png](ios-recovery-export.png) |
| Legacy read-only document preview | [ios-recovery-reader.png](ios-recovery-reader.png) |
| Read-only synchronization settings | [ios-sync-settings.png](ios-sync-settings.png) |
| Cached Markdown/table/image | [ios-offline-preview.png](ios-offline-preview.png) |
| Cached links with unavailable-document denial | [ios-cached-links.png](ios-cached-links.png) |
| Enrolled direct document after revocation | [ios-direct-revoked.png](ios-direct-revoked.png) |

## Reproduction and limits

Use an isolated iPhone 17 Pro Simulator on iOS 26.5. Native iOS screenshots are 1206×2622 pixels. Build the shared LittleLeonardo scheme with simulator ad hoc signing, then run the named PairingUITests through XCTest. Copy the three committed [fixture archives](fixtures) only into the task-owned app container at `Library/Application Support/LittleLeonardo/Corpus` after checking its identity. They supply synthetic `QA · Markdown`, `QA · Links` and `QA · Recovery` corpus archives for the optional cache/recovery cases. The recovery fixture uses the old `mode: git` serialized shape and preserves different base/current/published arrays. Seed data grants no network access and is not evidence of enrollment.

For desktop captures set `LEONARDO_GIT_RETIREMENT_EVIDENCE` to an owned temporary output directory and run `GitRetirementVisualTests` through `swift test`, recording compiler invocations. This is an NSHostingView component fixture inside XCTest, not a standalone XCTest application or a fresh packaged macOS process. The owner's running app is preserved.

No physical iOS device, two physical Macs, live VPN or Windows runtime is claimed. Windows remains deferred. Desktop direct synchronization is validated by native controller/runtime tests and real local HTTPS, not cross-platform acceptance. No release publication is included.
