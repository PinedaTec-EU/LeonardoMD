# PR #435 exact-source Little Leonardo validation

This directory records the bilingual iOS diagnostic flow from product code source `65a8076865346b45a0ae32c0af103884ec393d1d`. The English and Spanish UI tests passed on the named iPhone 17 Pro simulators running iOS 26.5. Both error notices show localized copy and an opaque reference; each reference appears in the corresponding local error log. The Spanish on-demand fixture also verified metadata-only enrollment, one explicitly opened file, and zero full snapshots.

The Spanish run first encountered stale pairing state in its task-owned simulator. After erasing only that dedicated QA simulator, the clean rerun passed. The failed attempt is retained in the local Xcode result bundle but is not used as acceptance evidence.

A separate existing localization follow-up remains visible in the English catalogue: its project description/pluralized host count still contains Spanish copy. It does not affect the diagnostic notice or log assertions in this PR.

The required packaged macOS Help smoke results will be appended after inspection of this candidate's actual app bundle.
