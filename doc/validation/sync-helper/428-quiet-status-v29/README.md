# Quiet sync status captures — v29

Captured from the production `SyncHelperPreferencesSection` in a native SwiftUI `NSHostingView` against product-code revision `2b8f9ed6b5daafa4654957bf8e9ffbe0826694c5`. The host was macOS 27.0.1. Status-section views are 532 × 260 points (1064 × 520 pixels); shared-project rows are 532 × 100 points (1064 × 200 pixels). Status and project fixtures use synthetic, non-sensitive values.

`status-online.png` and `status-checking.png` are byte-identical (`3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f`), showing that a healthy status stays unchanged during a check. `project-before.png`, `project-retrying.png` and `project-recovered.png` are byte-identical (`f9a1754404e0d1cdee7a65bb48c3cfb07aee0ef63a14664f6b3fea87bfcea2c6`), showing that transient retries do not move the shared-project row. Other captures show preserved recovery diagnostics, the red error state, and the approval action.

This is native component evidence for layout and state presentation. It does not claim signed-helper health, a fresh packaged-process check, or hosted beta installation/update acceptance. The evidence-only commit after `2b8f9ed6b5daafa4654957bf8e9ffbe0826694c5` does not change product code; only the compilation ledger and capture artifacts are added.
