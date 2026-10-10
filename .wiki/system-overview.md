# System overview

- `LeonardoApp`: AppKit application lifecycle and window ownership; SwiftUI presentation; native NSTextView editor; shared premium controls; per-window session orchestration.
- `LeonardoCore`: Foundation file/project/configuration services, conflict-aware document snapshots, and asynchronous system Git adapter.
- `LeonardoSync`: shared offline corpus, pairing consent, credential/registry persistence and direct authorization contracts.
- `LeonardoSyncTransport`: bounded HTTP/TLS listener, pinned HTTPS client and authorized direct routes; native lifecycle/UI integration pending under [#92](https://github.com/PinedaTec-EU/LeonardoMD/issues/92).
- `LeonardoRender`: isolated WKWebView, bundled offline libraries, sanitized Markdown, lazy optional engines and PDF export.

`Package.swift` is the build definition. `scripts/build-app.sh` assembles a locally signed macOS bundle and includes the renderer resource bundle. Finder document registration is in `scripts/Info.plist`.

Portable project settings: `.leonardomd/project.json`. Global settings: Application Support/LeonardoMD/preferences.json. Local window/reader preferences must not be mixed into portable project metadata.

See `doc/adr/0001-native-macos-and-lazy-extensions.md` for the native/renderer decision.
