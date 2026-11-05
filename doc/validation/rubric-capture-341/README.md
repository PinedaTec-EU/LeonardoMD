# #341 macOS rubric capture evidence

This directory contains implementation-owned native captures and their observed
contexts/metadata. The fixture uses the production `RubricEditor` and
`DesktopSyncController` with isolated synthetic records; it does not pair a
device, share a document, or claim a fresh packaged-process launch.

## Visual states

- `en/rubric-linked-request.png` and `es/rubric-linked-request.png` show one
  targeted pending request waiting for **Little Leonardo**, with explicit
  cancellation.
- `en/rubric-linked-review.png` and `es/rubric-linked-review.png` show the
  returned drawing preview, editable label, **Save to library**, and **Save and
  insert** actions.
- The packaged help illustration is kept in each locale's `doc/guide/.../assets`
  directory as `rubric-linked-offline.png`; its sidecar records the helper-offline
  state and the **Refresh linked devices** action.

Every PNG has a matching `.context.json` and `.metadata.json` sidecar. The
metadata helper records the source revision, capture time, native viewport,
image dimensions, and SHA-256 bytes. The capture source commit is
`6463463` (`#341 Updated: capture linked request and review states`); subsequent
changes in this PR are documentation/package-only and do not alter the captured
production views.

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
- `python3 scripts/package-user-guide.py --web-output doc` followed by
  `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'`
  — deterministic package test passed.

The guide package was advanced to v14 after main added the Synchronization role
pages; the v14 package preserves those pages and the linked-rubric instructions.

Physical iOS, TestFlight distribution, and the mobile request/draw/send UI are
explicitly deferred to #342/#343. The helper-owned Mac transport fixture and
real HTTPS lifecycle are covered by the focused tests already in the branch.
