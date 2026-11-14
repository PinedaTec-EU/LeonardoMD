# HTTP 403 access-denial alert

Tracking: [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368), [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

The production macOS synchronization preferences showed the localized neutral
access-denied alert when a synthetic HTTP 403 could not yet be classified as a
device revocation or a removed project grant. The recovery asks the user to
check authorization on the source Mac, refresh the project list, and retry. It
does not claim which permission changed or expose the raw response.

| Locale | Route | Native viewport | Image | SHA-256 |
|---|---|---:|---|---|
| English | `/native/preferences/synchronization/connections` | 600 × 532 pt | [access-denied-en.png](access-denied-en.png) · [metadata](access-denied-en.json) · [context](access-denied-en.context.json) | `7485d699bb73b893d792383c0c4e47c2443f238d966a0bf539d7d67828f29526` |
| Spanish | `/native/preferences/synchronization/connections` | 600 × 532 pt | [access-denied-es.png](access-denied-es.png) · [metadata](access-denied-es.json) · [context](access-denied-es.context.json) | `036377a6e81866edafa4a7a367041ab79cd2646583a455b7c2bee0f75d5a91ae` |

Both captures are 1200 × 1064 px. OCR verified the localized recovery text
and confirmation button. The test used synthetic state and includes no device,
project, credential or document details. Capture source:
`caf23aeb5e4ed4198ddd31eeb057b760b2a00737`; build inputs and successful
compiler-recorded delta `44` are in [build-inputs.json](build-inputs.json).

This is desktop synchronization evidence. It is not Little Leonardo simulator,
physical device or TestFlight acceptance.
