# Instructional image provenance

These are content assets in the guide, not a substitute for current-head guide
rendering evidence. PNGs are unmodified originals; metadata and observed contexts
are stored beside them in each locale's `assets/`. The MDLZ builder excludes all
sidecars. Generated premium PNG diagrams are illustrations, not screenshots; their generation
provenance is recorded in each locale’s `assets/illustrations.provenance.json`.

| Locale assets | Original capture source | Observed state |
| --- | --- | --- |
| `en/es/assets/home.png` | `e457e86` | Actual Welcome component; isolated empty favorites/recents |
| `en/es/assets/palette.png` | `e457e86` | Actual palette editor; initial valid global palette |
| `en/es/assets/sync-sharing-v12.png` | `f1ecf7b` | Synchronization → Share from this Mac; one common service control; disabled helper/sharing; isolated empty content |
| `en/es/assets/sync-connections-v12.png` | `f1ecf7b` | Synchronization → Connect to other computers; same common service control; disabled Connect; isolated empty connections/copies |
| `en/es/assets/project-identities.png` | `175791211` | Actual macOS project-identity component at 400×160; local, outgoing selected-content and received roles; same meanings apply on iOS; synthetic role data, not a paired-device capture |
| `en/es/assets/updates.png` | `e457e86` | Actual update preferences; synthetic installed version, stable subscription, fake transport |
| `en/es/assets/activation.png` | `b8900bf` | Actual global activation dialog, synthetic source; copied byte-for-byte from `doc/validation/extension-recommendations/current/dialog-<locale>-global.png` |
| `en/es/assets/warnings.png` | `b8900bf` | Actual extension preferences/reset; copied byte-for-byte from `doc/validation/extension-recommendations/current/reset-<locale>.png` |
| `es/assets/ios-rubric-capture-es.png` | `577d8821cd3c146d54dc55b49cc1695c0a7ec2e9`, `PairingUITests/testMacRequestedRubricCaptureDrawsRestoresAndSendsOverPinnedHTTPS()` | Spanish iPhone18Pro/iOS27.0 Simulator sent-state derivative captured 2026-11-06; full drawing and preview states are retained under `doc/validation/little-leonardo/`; capture-only, no document grant |

Full capture revisions:
- `f1ecf7b`: `0bc5a737bbbb8e38407a079c70b34cb896aa3064`.
- `e457e86`: `e457e86eccade662825253d4f94dc3a20999edf9`.
- `b8900bf`: `b8900bf14f17aba18e4e89cb141c392048a5314f`.

New photographs use the opt-in `UserGuideFeatureCaptureTests` fixture, one
language per process:

```sh
LEONARDO_GUIDE_FEATURE_EVIDENCE=/tmp/guide-photos LEONARDO_NATIVE_CAPTURE_LANGUAGE=en swift test --skip-build --filter UserGuideFeatureCaptureTests
```

Build the current tests first using the repository compilation recorder.
Repeat with `es`. The fixture never starts a sharing service or pairs a real
device, installs an update, sends a proposal or launches the packaged product.
Home, palette and update illustrations retain their original `e457e86` capture
revision; the synchronization pages were recaptured at `f1ecf7b` after the role
reorganization and common lifecycle composition. Historical pre-role originals
are preserved under `doc/validation/sync-helper/accepted-component-capture/`
and `previous-guide/`. Keep the actual original capture revision when reusing
an unchanged component; do not attribute an older capture to changed UI.
For changed UI, recapture and replace both locales with new canonical metadata.

The [#342](https://github.com/PinedaTec-EU/LeonardoMD/issues/342) mobile capture is also preserved in
`doc/validation/little-leonardo/ios-rubric-capture-es.png`; the adjacent JSON
sidecars record the exact source/test and SHA-256 values. Its response bytes are
recorded separately from the screenshot. The Mac side is a synthetic owned
fixture, so this evidence does not claim physical-device, App Store/TestFlight
or production-network acceptance.

Classic rotation capture for [#386](https://github.com/PinedaTec-EU/LeonardoMD/issues/386):
`assets/ios-rubric-classic-landscape.png` in both locales is a uniformly reduced
400×184 derivative of the original native iOS Simulator full-display capture in
`doc/validation/mobile-classic/rubric-landscape.png`. The application UI is Spanish
in both locale illustrations; English captions identify this explicitly. The
original, timestamp, device/runtime, source-input mapping and image hash remain
in that evidence directory. This is an actual signed simulator app talking to
the synthetic Mac TLS fixture, not a generated concept or physical-device claim.
