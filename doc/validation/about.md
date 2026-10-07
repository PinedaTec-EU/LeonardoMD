# Branded About

Tracking: [issue #27](https://github.com/PinedaTec-EU/LeonardoMD/issues/27).

This change is stacked on [PR #8](https://github.com/PinedaTec-EU/LeonardoMD/pull/8), with explicit owner authorization. Retarget its PR to `main` after the MVP integrates; do not merge it into the MVP feature branch.

Open **LeonardoMD → Acerca de LeonardoMD** to show the approved banner at its full aspect ratio. The app delegate retains one About window controller, including after closing it. Reopening the menu brings that window forward.

Version and build are read from the running application's Info.plist. The package starts at version `0.1.0`, build `1`, consistent with the automatic-update PR's initial metadata. SwiftPM execution without a version reports development rather than inventing one. There is no repository version-bump workflow.

Focused regression command: `swift test --filter ApplicationVersionTests`. Full validation: `swift test` and `./scripts/build-app.sh`. Verify the packaged About, not a generated mockup, for visual acceptance.

Approved asset: `Sources/LeonardoApp/Resources/AboutBanner.png`. Generated with built-in imagegen, using the Kopernicus Arx branding as a reference. Final edit prompt: retain the dense pencil-stroke L and lighten eonardo to roughly one-third stroke density, preserve the previously approved dense M/D and sparse ark/own, branding and Renaissance composition.

Local validation on 2026-10-07: focused version tests (3) and the full Swift test suite passed; release packaging and ad-hoc signing passed. The packaged About accessibility tree exposes the banner and `Versión 0.1.0 · compilación 1`. Native screenshot output was too small/opaque to prove the banner layout; final visual capture and independent judge remain pending before merge.
