# Project file visibility

`GlobalPreferences.showNonDocumentFiles` is a saved, off-by-default preference shared by macOS and Little Leonardo. `LeonardoProjectFileVisibility` owns the supported-extension policy for each surface. macOS treats `.mdlz` as a document; Little Leonardo does not. Little Leonardo reads valid `.mdlf` and `.mdlr` files through the Leonardo-aware preview in read-only mode; received forms cannot be filled or submitted.

The preference filters project tree rows, local project search results, remote catalogue browsers and pending remote “New files” notices. Search composes this visibility predicate with the existing project authorization filter; visibility never grants file access or changes synchronization. Markdown-linked local images remain available to document rendering even while their standalone files are hidden.

When the setting changes, the active sidebar tree and search results refresh. External preference-file changes refresh search when they change this setting. Focused regressions cover default-off search, enabling/disabling it, and remote review notices with synthetic `.md` and `.png` entries.

Implementation and delivery tracking: [#472](https://github.com/PinedaTec-EU/LeonardoMD/issues/472), [#476](https://github.com/PinedaTec-EU/LeonardoMD/issues/476), and [PR #473](https://github.com/PinedaTec-EU/LeonardoMD/pull/473).

Peer upload exclusion is enforced separately from list visibility. The receiving
side validates the base, proposed, current, and resolved snapshots against its
excluded extensions before file writes; persisted transaction journals repeat
that check during recovery. This protects older manifests and crafted proposals
that contain formats hidden by the receiving view. See
[#491](https://github.com/PinedaTec-EU/LeonardoMD/issues/491).
