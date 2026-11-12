# Favorites and welcome lists

Tracking: [#137](https://github.com/PinedaTec-EU/LeonardoMD/issues/137).

File → Favorites toggles the active document or project; unavailable
contexts are disabled and checked items are already favorites. The welcome
screen groups favorites by type and displays one recent-history category at a time through native segmented tabs. Stars share the same
membership, including filled stars on recent rows that are already favorites.
Favorites remain when recent history is cleared or evicted. Missing targets
stay listed with opening disabled and their star available for removal.

`GlobalPreferences.favorites` stores typed normalized URLs independently of
recent limits. Configuration merges apply membership changes, preserving
independent changes from other windows. Existing preference files default to
an empty favorites collection. Existing session polling refreshes other windows.

Project favorites also store an optional palette. Their Theme dropdown
appears beside favorite rows and matching starred Recents rows; Inherit restores
portable project/global appearance. Opening through either list or the native
Recents menu refreshes the association from local preferences. Document favorites
have no theme selector. Palette overrides use the catalog tokens without changing
global or project settings. Detaching a project, opening a standalone document or
saving a standalone copy restores normal global appearance. Workspace grouping
was removed under [#305](https://github.com/PinedaTec-EU/LeonardoMD/issues/305).
Previously stored workspace favorites/recents remain decodable but are absent
from navigation and cannot override appearance.
Membership merges key on kind/path; independent metadata changes survive stale
writers without duplicating or resurrecting removed favorites.

Tracking: [#300](https://github.com/PinedaTec-EU/LeonardoMD/issues/300).
`FavoriteThemeTests` and `FavoriteAppearancePersistenceTests` cover persistence,
Recents opening, retired workspace metadata isolation, context switching, custom-token inheritance,
session isolation and concurrent metadata/membership writes.

`FavoritesTests` covers restart persistence/removal, concurrent window changes,
clearing recents, native menu targets/checkmarks, path identity and availability.
The opt-in `LEONARDO_FAVORITES_CAPTURE` test renders the real SwiftUI welcome view
through `NativeViewCaptureSupport`, using temporary sample paths. The committed
captures are native component evidence, not packaged-app startup evidence.

Fresh packaged-process startup was not checked: the owner's installed app was
running and retained product-wide single-instance ownership. No user app was
terminated. Launch validation must follow `./launch.sh --qa` when ownership is
available.


## Historical native capture evidence (before workspace removal)

Captured on 2026-10-15 through macOS NSHostingView, with synthetic fixtures.
Browser/URL: not applicable (native macOS SwiftUI). Route: document-free welcome
screen. `source-hashes.json` identifies the exact source inputs, including the
capture harness, independently of the evidence commit.

- `welcome-en.png`, `welcome-es.png`: 1100×1150 points, paperWhite; filled
  stars for three kinds, outline star on a recent project, unavailable file.
- `removed-project-es.png`: 760×850 points, saved-items component after removing
  a project favorite; its recent row now has an outline star.
- `welcome-narrow-dark-es.png`: 600×600 points, graphiteGlass, Spanish; clipped
  lower content is accessible by the welcome ScrollView.

Recent documents are empty in this native test host; production uses the same
NSDocumentController history as the existing File menu. This task does not
change the separate native-history CI limitation tracked by #95.

Reproduce capture generation from the checkout with the source-PR recorder:

```sh
LEONARDO_FAVORITES_CAPTURE=/tmp/leonardo-138-captures python3 scripts/compile-and-record.py --pr-number 138 -- swift test --filter FavoritesTests
```

Eight focused cases passed with captures enabled. The full Swift suite passed
after main reconciliation; exact-head GitHub CI validates the final test harness
and release ledger. Component captures do not claim a fresh packaged process.
