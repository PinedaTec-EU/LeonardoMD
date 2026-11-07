# Little Leonardo Classic presentation

Owner-selected design: [#386](https://github.com/PinedaTec-EU/LeonardoMD/issues/386), [PR #387](https://github.com/PinedaTec-EU/LeonardoMD/pull/387). MobileClassic reads PaletteCatalog.leonardoClassic, not an independent color catalog. No Premium or theme selector. LaunchScreen is the static brand surface; MobileStartupView remains only during actual local preparation. About reads installed bundle metadata, with offline help/privacy and legal disclosures. The mobile MIT disclosure mirrors the root LICENSE (drift-tested); MarkdownLegalResources exposes the renderer’s existing bundled notices/licenses without a second vendored copy.

Rubric capture is fullScreenCover with a stable NavigationStack. Only accepted editable drawing expands when available width exceeds height; manuallyExpanded is the rotation-lock alternative. Portrait restores the normal page. Preview/frozen/blocked/submitted states stay outside editable expansion. One parent-owned LeonardoRubric backs both layouts; canvas points remain in portable 3:1 coordinates. Commit an in-progress sampled stroke at resize/disappearance, subject to the same portable limits and live authorization gate. Rotation does not invoke send.

Native acceptance extends PairingUITests/testMacRequestedRubricCaptureDrawsRestoresAndSendsOverPinnedHTTPS using the real opt-in Mac TLS fixture. Never claim generated concepts as application evidence. Packaged bilingual Help smoke and integration with demo/cache PRs remain separate delivery gates; see PR evidence for actual outcomes.

PR387 merge/TestFlight publication is now explicitly owner-authorized. The compact iPhoneSE3/iOS26.5 rubric test also asserts that a portrait label keyboard does not trigger expansion. Publication uses the existing Apple app/Owner Internal group; no signing or account policy change is requested. Main reconciliation, fresh evidence/review and packaged Help remain prerequisites; a locked GUI is not a passing check.

The PR branch has been refreshed onto accepted main0.3.1045, and its combined guide is now v25. Guide v23 references above describe the earlier checkpoint. Final reconciliation after demo/cache and actual packaged Help acceptance are still required.

- Accepted demo PR383 (99ac320) is reconciled. Startup prepares both local demo copies before reload; the library keeps demo entries reachable when there are no paired projects, with the branded connection panel inside the project section. Demo preview/source/help now use Classic while preserving real renderer form callbacks, save/reset and accessibility IDs. Guide25 combines accepted demo and Classic chapters;3 package tests pass. Final cache/diagnostic reconciliation and exact-head native/packaged QA remain pending.

- Follow-up [#389](https://github.com/PinedaTec-EU/LeonardoMD/issues/389): real root title remained blank after launch; inline title fixes pixels plus semantic assertion. Sourcea8a0555 focused native1/1 passes; demo continuation3/3 passes. Compilation entry22; cached demo answers remain separate from synchronization.

- Updated mobile FAQ/privacy on source0939fe9 verified with signed SE3/iOS26.5 native About flow1/1; entry23. Compact native originals and provenance are in doc/validation/mobile-classic/compact. Complete final-cache and macOS bundled Help gates remain pending.
