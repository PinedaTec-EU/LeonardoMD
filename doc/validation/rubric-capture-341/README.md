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
`17cd16d4e0d8a971f34832814aef68b6257dc84f` (`#350 Fixed: preserve pending
cancellation on reopen`). The capture run used the recorded build with
`--skip-build`, and the metadata records the exact final revision.

## Recorded validation

All compiler-bearing commands used the repository recorder for PR #349. The
successful cumulative build delta is recorded in `deploy/version/entries/349.yaml`.

- Earlier focused protocol/store/UI invocations for deltas 1–6 passed after
  their corrective edits; failed compile/test attempts were not counted.
- Earlier recorded validation through delta 25 remains in the commit history;
  it covered the helper-owned TLS lifecycle, guide v14, persistence,
  injected-clock ordering, source-context insertion guards and the complete
  lifecycle matrix.
- `swift test --filter RubricGuideCaptureTests` — deltas 7, 9–14 passed; the
  opt-in fixture was skipped when no capture directory was supplied.
- `swift test --filter RubricCaptureTests` — delta 8 passed (four tests).
- `swift test --filter BundledUserGuideTests` — delta 15 passed (five tests,
  both locales and 16 packaged PNGs).
- `LEONARDO_RUBRIC_GUIDE_CAPTURE=<temporary directory> swift test --skip-build
  --filter RubricGuideCaptureTests` — passed with English/Spanish offline,
  pending-request, and response-review captures.
- Recorded `swift test --filter RubricCaptureTests` — delta 26 passed (12
  tests), delta 27 passed (13 tests), delta 28 passed (14 tests), delta 30
  passed (15 tests), and delta 32 passed (15 tests). The final run covers stable-ID lost acknowledgement,
  late completed-response recovery before tombstoning, authenticated missing
  request handling, capacity protection for unresolved/unsaved records,
  backwards-clock lifecycle ordering, and cancellation while create is in
  flight. The cancellation regression verifies a `notFound` cancel is retained
  as a local intent, the late create is compensating-cancelled remotely, and no
  review/save path receives it.
- Recorded `swift test --filter BundledUserGuideTests` — delta 31 passed (five
  tests, both locales, v14 packages and preserved personal-copy fixtures).
- Recorded full `swift test` — delta 33 passed: 363 XCTest cases with 30
  expected opt-in skips and 42 Swift Testing cases, including real TLS rubric
  request/accept/response coverage; no failures.
- `LEONARDO_RUBRIC_GUIDE_CAPTURE=$PWD/doc/validation/rubric-capture-341 swift
  test --skip-build --filter RubricGuideCaptureTests` — passed and regenerated
  the English/Spanish full-height request and review captures from source
  `17cd16d4e0d8a971f34832814aef68b6257dc84f`.
- `python3 scripts/package-user-guide.py --web-output doc` followed by
  `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'`
  — deterministic package test passed.

The guide package was advanced to v14 after main added the Synchronization role
pages; the v14 package preserves those pages and the linked-rubric instructions.

Physical iOS, TestFlight distribution, and the mobile request/draw/send UI are
explicitly deferred to #342/#343. The helper-owned Mac transport fixture and
real HTTPS lifecycle are covered by the focused tests already in the branch.
