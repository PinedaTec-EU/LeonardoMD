# Little Leonardo error and Help evidence

Product source: `dcbad8240aa4e9424260dfe3b664145811a3ba69` (PR #435 localization correction and fixed diagnostic categories). The evidence-only commit adds this folder; application sources and build inputs do not change there.

Captures are original XCTest attachments from the iOS 27.0 iPhone 18 Pro Max Simulator (`0C5D5C27-1EBC-4C69-BA40-CAEE89F49750`), 440 × 956 points / 1320 × 2868 pixels. The Spanish pairing test shows a short localized alert and the matching `op=pairing kind=network code=-1004` local entry. The English test shows the English title, message and single `OK` action. The mobile Help test opens Ayuda through Library → Settings → About → Help.

All three focused UI tests passed 1/1. Exact result bundle names, UTC times, image hashes and screen state are in `manifest.json`.

The separate Mac sync fixture was unreachable from this simulator (`NSURLErrorDomain -1004`), so enrollment and refresh acceptance are not claimed. This mobile Ayuda capture does not satisfy the mandatory Spanish/English packaged macOS Help smoke. That acceptance remains pending because the user’s running production LeonardoMD instance must remain untouched. The physical 338,658-byte image issue remains open as well.
