# Native update acceptance evidence

Reviewed source: `4f276a62a3541d8c9bd5570bbc458f24cc00bd9f`.
Captured 2026-10-08 on macOS 27.0.1 (26A434), arm64. Native AppKit/Sparkle windows; browser and route N/A. Screenshots are unedited native screencapture window captures, including native shadows; no desktop or personal documents included. Main window viewport 1260×850 points. Dialog viewport varies with Sparkle state; PNG dimensions below.

Executable UUID of both release build at reviewed source and installed fixture: `008B889B-4808-3F2A-A1D6-27373D4BC1B0` (arm64). Fixture metadata only: executable/display name UpdaterQA17, isolated bundle identifier `eu.pinedatec.LeonardoMD.qa17current`, beta versions build2→3, loopback HTTP feed port8157 and test-only ATS exception. Fixture is Developer ID signed; production metadata remains HTTPS without ATS exception. No signing private key or notarization credentials are included.

## Observed sequence and reproduction

Build reviewed source with Scripts/build-app.sh. Copy the bundle to a disposable fixture. Set fixture identity/name, beta channel, public Ed25519 key, versions 0.1.1-beta.1/build2 and 0.1.1-beta.2/build3, and loopback feed. Sign nested Sparkle helpers and both apps with Developer ID. Archive newer fixture and use Sparkle generate_appcast with its separate beta Keychain account. Serve via `python3 -m http.server 8157 --bind 127.0.0.1 --directory /tmp/leonardo17-current`. This test-only loopback exception must not be used in distribution.

1. Without configured public key, manual check reports unconfigured updates (`direct-dialog.png`).
2. With signed build3 appcast, manual check offers release notes and installation (`available.png`). Close the dialog to defer; application continues.
3. Download signed archive: ready-to-install dialog (`ready.png`).
4. Open synthetic draft.md, switch to editing and set `# QA\nUnsaved draft must survive update.\n`. Before the 700ms autosave, externally replace draft.md with `# QA\nExternal version.\n`. Click Install and Relaunch. Existing close guard blocks termination, keeps build2 and the unsaved draft (`blocked-close.png`).
5. Accept warning and Save a Copy to draft-copia.md. Original stays external version, copy contains unsaved draft. Retry Install and Relaunch. Actual executable replacement and relaunch succeed; About shows beta2/build3 (`installed.png`). Both file contents remain unchanged.
6. Same appcast now reports no update (`no-update.png`).
7. Copy archive, XOR one byte at midpoint; retain original signature and length, advertise build4/beta3 with new tampered.zip URL. Native updater rejects signature before installation (`invalid-signature.png`), stays build3.
8. Stop loopback server, manual check reports retrieval error (`network-error.png`). Open saved copy with server stopped; renderer displays exact saved draft (`offline-document.png`).
9. Enable automatic checks via app menu. `defaults read eu.pinedatec.LeonardoMD.qa17current SUEnableAutomaticChecks` returns1. Quit normally and relaunch; same read still1. Default false also survived actual build2→3 installation. These reads use only isolated fixture preferences.

This proves local updater behavior. It does not claim public HTTPS distribution or Gatekeeper/notarization acceptance. Public production publication is excluded by issue15 until distribution prerequisites exist.

| Capture | PNG pixels | SHA256 |
|---|---|---|
| direct-dialog.png | 618×592 | `f48a566af5453dcceeefcf49727a6cf37f9b4a87e88bcfe7f087403ab114fd5b` |
| available.png | 1428×1020 | `fb52ff9045cc5bbc84e7bd5ac1fc09a020d4859ef611ecf7ffcd84b1c203df29` |
| ready.png | 1024×506 | `6709fac17e4fd1ea8de85bf841645f59f04ed7b27c223147e07ada0cfbf3a028` |
| blocked-close.png | 2744×1924 | `b9104bbf9ca02996171464d1ff8bf2e6c5e23619df1863acbf73caf96ce0df6e` |
| installed.png | 1664×1408 | `ac13db2c6eebc58f01671471b54b3fc37fb3c0e552f3f94b63a930c0eb2e81b5` |
| no-update.png | 744×692 | `0ef09f5f39a50a7dbceecb8da277898672278b00d619f5616df0f2f0b6f53aff` |
| invalid-signature.png | 744×724 | `910235dafb061fad39d048ffedea663f70d6a2f6280902f2e23560b101f4be0a` |
| network-error.png | 744×692 | `27b0d57a49dccd777ccba94dd5ad3ef94697a32ecee9473da17d746ffef0a840` |
| offline-document.png | 2744×1924 | `2d0bf1c343e55ad3eaf4f03ed464247839a4c548610bf83b8a4a149d4cae481f` |
