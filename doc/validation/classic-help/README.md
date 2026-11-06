# Transparent Classic help acceptance

Tracking: [#375](https://github.com/PinedaTec-EU/LeonardoMD/issues/375), [PR #376](https://github.com/PinedaTec-EU/LeonardoMD/pull/376).

## Component captures

Captured source: `41ce6e01bea29ee2a319096575de08a74e62ccac`.
The following evidence-only commit adds this directory without changing app sources, test sources, guide packages, assets or compilation allocation. Map these captures to that reviewed head only after verifying that exact diff boundary. A later product edit invalidates the mapping.

Reproduce with `LEONARDO_VISUAL_EVIDENCE="$PWD/output/help-review" EVIDENCE_SHA="$(git rev-parse HEAD)" swift test --skip-build --filter BundledUserGuideTests` after a successful recorded compilation. The skip-build capture run passed five tests. The cached executable was compiled from the same product/test/resource content; only the ledger count and central version materialization advanced before capture. No installed-package claim is made for these component images.

Original WKWebView element captures, synthetic bundled guides, 1100×772 CSS/native points and 2200×1544 pixels. Engine compatibility versions and actual capture times are in the original context sidecars. Shared-helper metadata binds each original PNG digest. Both locales load all 16/17 images under the standard resource budget; alpha/corner and 1200×400 artwork bounds are asserted natively. Main guide revision 17 and standalone import revision 3 preserve older personal copies. Authored PNGs are generated illustrations, never app screenshots.

| Illustration | English | Spanish |
| --- | --- | --- |
| Journey | [capture](premium-journey-en.png) | [capture](premium-recorrido-es.png) |
| Package | [capture](premium-package-en.png) | [capture](premium-paquete-es.png) |
| Export alternatives | [capture](premium-export-en.png) | [capture](premium-exportar-es.png) |
| Agent import | [capture](premium-import-en.png) | [capture](premium-importar-es.png) |

## Packaged application smoke test

On 2026-11-06 at approximately 16:28–16:34 UTC, `LEONARDO_SOURCE_PR=376 ./launch.sh --qa` built and launched the real packaged executable from `be55d05`. Temporary identity: `eu.pinedatec.LeonardoMD.qa.e48f715432d847f290c69dfe6d127a0c`; PID 72700; version/build 0.3.1000/1000 (development QA provenance, not a published candidate). QA packaging verified executable/dependencies before opening. A fresh first window and real Help menu were observed with native CUA; the source app was not installed or substituted for the owner's app.

Passed in that same process:

- Help → Leonardo user guide / Ayuda → Guía de Leonardo opened Guide-v17-en/es working copies through the real menu.
- Classic palette and Parchment paper showed the transparent illustration without the prior pink panel. Mermaid, inline math, one-line mean, multiline underbraces, tagged box-counting equation (1), Vega chart, tables, image inventory and literal code examples were inspected via native accessibility and screenshots.
- With Math disabled, both languages exposed the original dollar-delimited underbrace/tag source. Math was restored to on; Mermaid/Charts remained on. Interface language was restored to English.
- Both chapter-4 practice links opened separate Fill-mode MDLR tabs. Synthetic names QA 375 / QA 375 ES survived Save → close → reopen. Test fields were cleared and saved afterwards; no existing nonempty answer was replaced.
- The temporary QA process quit normally; no Leonardo process remained running. User-installed application bytes were not changed.

The CUA screenshot observations are retained in the originating chat; the original image evidence in this directory is explicitly component capture evidence. No fresh final distribution startup, hosted beta installation, updater transition or relaunch is claimed. The source differs from the final capture source only by compilation allocation and canonical version materialization; runtime/help content is unchanged. These limitations are separate from signed beta publication.

## Automated validation

Full recorded Swift suite after main reconciliation: 365 XCTest tests, 15 documented skips, zero failures, plus package Swift Testing suites. Source PR compilation allocation: five successful author invocations (two full test runs, two focused test runs, one release QA build). Python scripts: 95 tests with seven documented skips; format plugin: 38 tests; packaging: 20 tests. Deterministic guide packaging passes. Exact-head CI and strict independent review remain required.
