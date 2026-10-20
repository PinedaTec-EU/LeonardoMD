# Branded About

Tracking: [issue #27](https://github.com/PinedaTec-EU/LeonardoMD/issues/27).

Historical integration context (2026-10-07): this change was stacked on [PR #8](https://github.com/PinedaTec-EU/LeonardoMD/pull/8), with explicit owner authorization. The About change subsequently integrated through PR #28; the original retargeting instructions are historical.

Open **LeonardoMD → Acerca de LeonardoMD** to show the approved banner at its full aspect ratio. The app delegate retains one About window controller, including after closing it. Reopening the menu brings that window forward.

Version and build are read from the running application's Info.plist. Current packaging derives version/build from `version.nfo`, initially `0.1.56` / `56`; see [the release-ledger workflow](../release-version-ledger.md). The original pre-ledger package used `0.1.0` / `1`. SwiftPM execution without a version reports development rather than inventing one. Source PRs now record release.feature.build deltas; release metadata is materialized by the shared ledger.

Focused regression command: `swift test --filter ApplicationVersionTests`. Full validation: `swift test` and `./scripts/build-app.sh`. Verify the packaged About, not a generated mockup, for visual acceptance.

Approved asset: `Sources/LeonardoApp/Resources/AboutBanner.png`. Generated with built-in imagegen, using the Kopernicus Arx branding as a reference. Final edit prompt: retain the dense pencil-stroke L and lighten eonardo to roughly one-third stroke density, preserve the previously approved dense M/D and sparse ark/own, branding and Renaissance composition.

Historical pre-ledger validation on 2026-10-07 (the version text below is retained as evidence for that revision): focused version tests (3) and the full Swift test suite passed; release packaging and ad-hoc signing passed. The packaged About accessibility tree exposes the banner and `Versión 0.1.0 · compilación 1`. Native screenshot output was too small/opaque to prove the banner layout; final visual capture and independent judge remain pending before merge.

## PR #248 scoped owner exception

For [PR #248](https://github.com/PinedaTec-EU/LeonardoMD/pull/248) only, the owner explicitly instructed on 2026-10-20: “fusiona, validare en el canal beta” (“merge; I will validate in the beta channel”). This direct instruction authorizes deferring the pre-merge native screenshots, packaged About visual verification, pointer interaction and visual acceptance of all sheets/dialogs changed by that PR until beta. It overrides those visual evidence requirements for this candidate only; it establishes no general exception for future changes.

Reason: a prior QA instance retains a detached application-modal alert that automation cannot expose for normal cancellation, preventing an independent product instance. Alternative pre-merge evidence is automated native sheet ownership, nesting, close/reopen, startup continuation, cancellation and stale-operation regression coverage, full tests and exact-head CI/package inspection. Correctness, data safety, current-head CI, release-ledger policy and the fresh strict judge remain mandatory. No visual check is marked passed. Appearance, pointer behavior and packaged first-window interaction remain a residual risk for owner acceptance in beta under [issue #247](https://github.com/PinedaTec-EU/LeonardoMD/issues/247).
