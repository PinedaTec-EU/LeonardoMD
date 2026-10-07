# Current-head native evidence

Reviewed source: `c9783e630a83d84e3c4167fceb6c64ff3cbc5831`.
Fresh captures 2026-10-08, macOS27.0.1 (26A434), arm64. Native AppKit/Sparkle, browser/route N/A. Main viewport1260×850points. Fixture same identity/metadata and reproduction as ../4f276a6/README.md.

Only packaging scripts, packaging tests and docs changed after 4f276a6. A release rebuild on c9783e6 produces the same executable UUID `008B889B-4808-3F2A-A1D6-27373D4BC1B0`. The running isolated fixture and rebuilt release executable have identical __TEXT/__text output SHA256 `e122f9ffe85a1af812b92004fbb412873338a478738e03475aea85c3840c2e84` (otool -s __TEXT __text, omit first path line). Thus the prior signed install/relaunch and unsaved-conflict captures exercise exactly the current application code, with no source or UI change. Current captures repeat available-update/release-notes, invalid-signature rejection, no-update, network-error and offline rendering after this rebuild. Network-error uses a native screen-region capture of the exact alert bounds3710,325,260,234points because window capture omitted native material background. Others are native window captures, unedited.

Packaging validation:11/11 tests pass, full Swift suite94 tests pass, actual Keychain public key matches embedded key. Final local beta0.1.1-beta.3 build4 signed DeveloperID+Ed25519, not notarized. ZIP SHA256 `ffb918410b71bea3f9134e0b33541de53abff520671cd8052e67413c72b3e8d1`. Public feed/release publication remains unperformed. Account lookup uses only generate_keys -p, no private key exports.

Current isolated automatic-check preference still1 after relaunch; original and saved draft copy remain respectively external version and unsaved draft bytes.

| Capture | PNG pixels | SHA256 |
|---|---|---|
| network-error.png | 520×468 | `e6be8bb87e8a1494ede78bd1eec4ca4a0b99aac0dd001ba84e76357604f8647d` |
| invalid-signature.png | 744×724 | `910235dafb061fad39d048ffedea663f70d6a2f6280902f2e23560b101f4be0a` |
| offline-document.png | 2744×1924 | `de5bed71cf0c8af1c0cb601e5829a83a511a465d057423d848141583f0639932` |
| available.png | 1428×1020 | `fffb3e87cf868ebc5b5d85d7b2539d965176c97dcc8e2f07f6cab43c0f319502` |
| no-update.png | 744×692 | `0ef09f5f39a50a7dbceecb8da277898672278b00d619f5616df0f2f0b6f53aff` |
