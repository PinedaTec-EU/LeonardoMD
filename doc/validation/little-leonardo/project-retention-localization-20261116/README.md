# Project offline-retention copy — PR #435

The project-level **Keep offline** caption matches the selected locale. The English and Spanish UI tests passed on iPhone 17 Pro Simulator 26.5, each with one test and no failures. The synthetic loopback fixture includes one newly shared project, current files, and a retained-download failure.

| Locale | Capture | Test | Result bundle |
|---|---|---|---|
| English (`en_US`) | [project-retention-en.png](project-retention-en.png) · [context](project-retention-en.context.json) | `OnDemandSyncUITests/testEnglishSharedDownloadFailureLocalizesVoiceOverCopy()` · [test summary](english-test-summary.json) | `test_sim_2026-11-16T13-00-23-789Z_pid23125_d0b7890c.xcresult` |
| Spanish (`es_ES`) | [project-retention-es.png](project-retention-es.png) · [context](project-retention-es.context.json) | `OnDemandSyncUITests/testCatalogueContextRetentionAndSeparateCache()` · [test summary](spanish-test-summary.json) | `test_sim_2026-11-16T13-02-56-191Z_pid23125_0b5badc1.xcresult` |

Each original screenshot is 1206 × 2622 px from a 402 × 874 point native viewport; both are unmodified XCTest captures. The screen and locale-test changes were captured from the PR worktree immediately before they were committed in product-source commit `49052f4d4bb2b1bdaabf3bd023e01a185976445e`. The original contexts could not identify a source SHA, so this is a source mapping rather than a claim that XCTest embedded the Git revision. The captured view and test source are the files committed in that source SHA. The final PR adds only evidence, agent documentation, and the compilation ledger after that product-source commit.

The Spanish host-count line visible in both captures is the separately tracked issue [#457](https://github.com/PinedaTec-EU/LeonardoMD/issues/457); this PR fixes only the offline-retention caption tracked by [#459](https://github.com/PinedaTec-EU/LeonardoMD/issues/459).

The bilingual Guide v74 already explains that project-level **Keep offline** includes current and future files in chapter 15; this copy correction adds no new user instruction, so the help sources and packaged guide revision remain unchanged. The macOS packaged Help smoke for the current validation build remains recorded in the PR description.
