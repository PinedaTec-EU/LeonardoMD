# Favorite appearance

Tracking: [#300](https://github.com/PinedaTec-EU/LeonardoMD/issues/300).

The implementation-owned captures render the actual `SavedItemsView` and
`FavoriteThemePicker` through the existing XCTest `NativeViewCaptureSupport`
harness, with synthetic folders and isolated preferences. No XCTest executable
was packaged or launched as a standalone GUI app.

- `favorite-themes-en-900.png`: English, light, 900×620 points.
- `favorite-themes-es-900.png`: Spanish, light, 900×620 points.
- `favorite-themes-es-600.png`: Spanish, dark, 600×620 points.

Each capture shows project/workspace favorites with their dropdowns and a starred
recent project sharing the same association. The narrower capture keeps the
controls visible while truncating long paths. Native bitmap pixel dimensions and
capture times are recorded in the JSON sidecars. Browser metadata is inapplicable.
The source manifest identifies the exact product/test source captured locally;
local captures preceded the evidence commit. CI captures the same states under
its exact `EVIDENCE_SHA` in the existing visual-evidence artifact.

These are native component captures, not packaged-process startup evidence.
The owner's installed LeonardoMD process was running and was preserved; no
fresh packaged-process or multi-process GUI validation is claimed. Session
isolation and cross-writer persistence are exercised through application tests.

`FavoriteThemeTests` verifies Recents opening and refresh in an already initialized
session, independent session appearance, workspace containment/manager precedence,
project switching, inheritance/custom tokens, document exclusion and concurrent
membership/metadata writes. `FavoriteAppearancePersistenceTests` verifies Codable
roundtrips, stable kind/path identity and merging independent appearance changes.
