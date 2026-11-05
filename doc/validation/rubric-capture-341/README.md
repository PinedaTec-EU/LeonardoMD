# #341 macOS rubric capture evidence

This directory contains implementation-owned native captures and their observed
contexts/metadata. The fixture uses the production `RubricEditor` and
`DesktopSyncController` with isolated synthetic records; it does not pair a
device, share a document, or claim a fresh packaged-process launch.

## Visual states

- `en/rubric-linked-request.png` and `es/rubric-linked-request.png` show one
  targeted pending request waiting for **Little Leonardo**, with explicit
  cancellation, in a full-height 760-point native editor view.
- `en/rubric-linked-review.png` and `es/rubric-linked-review.png` show the
  returned drawing preview, editable label, **Save to library**, and **Save and
  insert** actions in the same full-height native editor view; they are not
  cropped component fragments.
- The packaged help illustration is kept in each locale's `doc/guide/.../assets`
  directory as `rubric-linked-offline.png`; its sidecar records the helper-offline
  state and the **Refresh linked devices** action.

Every PNG has a matching `.context.json` and `.metadata.json` sidecar. The
metadata helper records the source revision, capture time, native viewport,
image dimensions, and SHA-256 bytes. These four request/review captures were
regenerated from the final production fixture at source commit
`efc9012fc479e3859d929b3a5fcee96768bc0998` (`#350 Fixed: remove rubric EOF
whitespace`). The capture run used the recorded full-suite build with
`--skip-build`; the source change after that build was whitespace-only, and the
metadata records the exact final revision.

## Recorded validation

All compiler-bearing commands used the repository recorder for PR #349. The
successful cumulative build delta is recorded in `deploy/version/entries/349.yaml`.

- Focused protocol/store/UI invocations for deltas 1–6 passed after their
  corrective edits; earlier failed compile/test attempts were not counted.
- `swift test --filter RubricGuideCaptureTests` — deltas 7, 9–14 passed; the
  opt-in fixture was skipped when no capture directory was supplied.
- `swift test --filter RubricCaptureTests` — delta 8 passed (four tests).
- `swift test --filter BundledUserGuideTests` — delta 15 passed (five tests,
  both locales and 16 packaged PNGs).
- `LEONARDO_RUBRIC_GUIDE_CAPTURE=<temporary directory> swift test --skip-build
  --filter RubricGuideCaptureTests` — passed with English/Spanish offline,
  pending-request, and response-review captures.
- Recorded `swift test --filter RubricCaptureTests` — delta 17 passed (5 tests),
  including lost create/status acknowledgement recovery with one stable UUID.
- Recorded `swift test --filter RubricExchangeTests` — delta 18 passed (9 tests),
  including idempotent authority create retry.
- Recorded `swift test --filter BundledUserGuideTests` — delta 19 passed (5
  tests, both locales, v14 packages and preserved v13 personal-copy fixtures).
- Recorded full `swift test` — delta 20 passed across the macOS XCTest and Swift
  Testing suites; opt-in evidence tests remained skipped unless explicitly
  enabled. Real TLS rubric request/accept/response coverage passed in the same
  run.
- Recorded `swift test --filter RubricGuideCaptureTests` with the opt-in capture
  directory — delta 21 passed and regenerated the English/Spanish request and
  review captures from the final source.
- Recorded `swift test --filter RubricCaptureTests` — delta 22 passed (6 tests),
  including injected-clock retention, rollback ordering and terminal-state
  monotonicity.
- Recorded full `swift test` — delta 23 passed across the macOS XCTest and Swift
  Testing suites; opt-in evidence tests remained skipped unless explicitly
  enabled. Real TLS rubric request/accept/response coverage passed in the same
  run.
- `LEONARDO_RUBRIC_GUIDE_CAPTURE=$PWD/doc/validation/rubric-capture-341 swift
  test --skip-build --filter RubricGuideCaptureTests` — passed and regenerated
  the English/Spanish request and review captures from the final revision.
- `python3 scripts/package-user-guide.py --web-output doc` followed by
  `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'`
  — deterministic package test passed.

The guide package was advanced to v14 after main added the Synchronization role
pages; the v14 package preserves those pages and the linked-rubric instructions.

Physical iOS, TestFlight distribution, and the mobile request/draw/send UI are
explicitly deferred to #342/#343. The helper-owned Mac transport fixture and
real HTTPS lifecycle are covered by the focused tests already in the branch.
