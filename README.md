# PR 147 visual evidence

Source head: `48277a59a9dce6b743fd9f154b33cedb45d6219a`. Embedded CSS checked byte-for-byte against production preview.css at this head.
Capture: 2026-10-15 Europe/Madrid; Playwright WebKit on macOS.
Route: about:blank; synthetic metadata/document component via page.setContent.
Viewports: parchment and dark 1100x650; narrow light 520x650.
States: visible metadata and title, theme tokens set for parchment/red, dark/blue and light/blue.
Computed border-left color equals h1 color in every state. Captures visually inspected.
Limit: component evidence only; no packaged startup claim. Static CSS has no new interactive behavior.

Reproduce: open about:blank using playwright-cli with --browser webkit, then run `playwright-cli run-code --filename reproduce.js`. Script asserts color equality and writes /tmp/leonardo146-*.png. Body transitions disabled for deterministic captures.
