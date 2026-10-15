# Favorites and welcome lists

Tracking: [#137](https://github.com/PinedaTec-EU/LeonardoMD/issues/137).

File → Favorites toggles the active document, project or workspace; unavailable
contexts are disabled and checked items are already favorites. The welcome
screen groups favorites and recent history by type. Stars share the same
membership, including filled stars on recent rows that are already favorites.
Favorites remain when recent history is cleared or evicted. Missing targets
stay listed with opening disabled and their star available for removal.

`GlobalPreferences.favorites` stores typed normalized URLs independently of
recent limits. Configuration merges apply membership changes, preserving
independent changes from other windows. Existing preference files default to
an empty favorites collection. Existing session polling refreshes other windows.

`FavoritesTests` covers restart persistence/removal, concurrent window changes,
clearing recents, native menu targets/checkmarks, path identity and availability.
The opt-in `LEONARDO_FAVORITES_CAPTURE` test renders the real SwiftUI welcome view
through `NativeViewCaptureSupport`, using temporary sample paths. The committed
capture is native component evidence, not packaged-app startup evidence.

Fresh packaged-process startup was not checked: the owner's installed app was
running and retained product-wide single-instance ownership. No user app was
terminated. Launch validation must follow `./launch.sh --qa` when ownership is
available.
