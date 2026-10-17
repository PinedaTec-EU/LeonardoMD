# Home recent tabs and background

Tracking: [#156](https://github.com/PinedaTec-EU/LeonardoMD/issues/156). Related visibility bug: [#85](https://github.com/PinedaTec-EU/LeonardoMD/issues/85).

Native NSHostingView captures on macOS, 2026-10-17, with synthetic fixtures. Screen: document-free Home and its saved-items component. No browser/URL applies. `source-hashes.json` identifies the exact source inputs. These are component captures, not packaged-app startup evidence.

- `welcome-en.png`, `welcome-es.png`: 1100×1150 points, light palette, lettering above and flying machine below.
- `recent-document-es.png`, `recent-project-es.png`, `recent-workspace-es.png`: 760×650 points, each selected recent category, including the empty documents state. Favorites retain all three original groups.
- `removed-project-es.png`: favorite removal state, 760×850 points.
- `welcome-narrow-dark-es.png`: 600×600 points, dark palette.
- `welcome-600x400-es.png`, `welcome-1260x687-es.png`: short/ordinary-height canvases; lettering remains fully visible. Lists scroll below the fixed lettering area.

The native Picker owns selection and keyboard interaction. Each capture initializes its selected category. Existing row opening, availability and star actions are reused.

Validation: focused FavoritesTests passed (9 cases with captures enabled). Full Swift suite passed with no failures; opt-in unrelated checks remain skipped. Successful compilation commands are recorded in source PR #157's ledger entry (build delta 3). A geometry regression covers 320×240 through 1600×1000 canvases.

Reproduce with `LEONARDO_FAVORITES_CAPTURE=/tmp/leonardo-home-157 python3 scripts/compile-and-record.py --pr-number 157 -- swift test --filter FavoritesTests`.

The installed app was running and retained product-wide single-instance ownership. No user process was terminated. Fresh packaged-process launch remains unverified and must use `./launch.sh --qa` when ownership is available.
