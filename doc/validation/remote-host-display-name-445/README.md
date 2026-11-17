# PR #445: Little Leonardo host display name

## Current native evidence

- Product source: `5d33e34afd3680cbac6451cd3c9181272c6dc27b`. The following candidate updates only the PR ledger count and adds evidence; the Little Leonardo product inputs are unchanged.
- App and scheme: `Mobile/LittleLeonardo.xcodeproj`, `LittleLeonardo`, Debug.
- Device: iPhone 17 Pro Simulator, iOS 26.5, UDID `1FCBDCDA-87B0-4E70-8686-2B417D479EC9`.
- Screen: native SwiftUI `Biblioteca`. The capture shows the saved local alias **Mac QA**, `1 proyecto · 1 por revisar`, no endpoint in the host row and no empty **En este dispositivo** section. The only project and all connection data are synthetic.
- Capture: [display-name-singular-count-es.png](display-name-singular-count-es.png); [context](display-name-singular-count-es.context.json); [metadata](display-name-singular-count-es.metadata.json). Captured 2026-11-17 09:13:23 UTC at 402 × 874 native points / 1206 × 2622 pixels. This is a native screen; browser and CSS viewport do not apply.

## Validation

- `MobileConnectionDisplayNameTests`: 5 passed, 0 failed. Coverage includes legacy decoding, hostname/IP suggestions, rename persistence, preserving connection identity and grants, and the asynchronous recovery/relaunch race from #449.
- `OnDemandMobileAcceptanceFixtureTests.testServeOnDemandMobileFixture`: 1 passed, 0 failed.
- `OnDemandSyncUITests.testLocalDisplayNameAndSingularProjectCountCapture`: 1 passed, 0 failed. The exact-source flow restored Demo from settings when needed, removed it explicitly, verified the local section disappeared, paired with an isolated synthetic Mac, renamed it, and captured the final library.
- XcodeBuildMCP `snapshot_ui` confirmed the rendered host accessibility label `Mac QA, 1 proyecto · 1 por revisar`. After the capture, Demo was restored.
- Deterministic bilingual guide packaging tests: 3 passed, 0 failed. Guide v92 EN/ES hashes are recorded in [`doc/guide/README.md`](../../guide/README.md).
- Fresh packaged macOS Guide v92 Help passed in English and Spanish: representative Mermaid, math (including disabled-extension fallback and the tagged box-counting equation), chart, image, table, literal code and practice-form save/reopen checks. Exact instance identity, bundle hashes and teardown are in [the packaged Help manifest](../little-leonardo/packaged-help-v92-20261117-pr445.json).
- The source PR compilation delta is `build: 27`; failed compile/test attempts were not counted.

The simulator could not route its own `127.0.0.1` to the Mac. The successful fixture used `LEONARDO_ON_DEMAND_QA_HOST` with an active Mac interface reachable from the simulator, ad-hoc simulator signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`), a fresh `.qa-fixture-owned` directory and port 46987. The private interface address is intentionally omitted. Do not use production Mac data.

Physical-device/TestFlight acceptance is separate and remains outstanding until the accepted materialized build is processed and assigned to the internal group.

## Reproducing the native screen

Use XcodeBuildMCP with the project and scheme above and a fresh iPhone 17 Pro simulator. Build for testing with ad-hoc simulator signing, start `OnDemandMobileAcceptanceFixtureTests.testServeOnDemandMobileFixture` on an active Mac interface reachable from the simulator, and pass the same `LEONARDO_ON_DEMAND_QA_ROOT`, `LEONARDO_ON_DEMAND_QA_MODE=display-name` and `LEONARDO_ON_DEMAND_QA_HOST` values to the test runner. Run only `LittleLeonardoUITests/OnDemandSyncUITests/testLocalDisplayNameAndSingularProjectCountCapture`. The fixture requires port 46987 and a fresh `.qa-fixture-owned` marker. No browser route applies.

The earlier [library-incoming-project.jpg](library-incoming-project.jpg) capture is historical evidence from its own source; the current exact-source screenshot above is the acceptance capture for #442/#444.
