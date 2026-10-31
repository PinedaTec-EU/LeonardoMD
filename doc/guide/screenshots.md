# Instructional image provenance

These are content assets in the guide, not a substitute for current-head guide
rendering evidence. PNGs are unmodified originals; metadata and observed contexts
are stored beside them in each locale's `assets/`. The MDLZ builder excludes all
sidecars. Generated SVG diagrams are illustrations, not screenshots.

| Locale assets | Original capture source | Observed state |
| --- | --- | --- |
| `en/es/assets/home.png` | `e457e86` | Actual Welcome component; isolated empty favorites/recents |
| `en/es/assets/palette.png` | `e457e86` | Actual palette editor; initial valid global palette |
| `en/es/assets/mobile.png` | `e457e86` | Actual Little Leonardo preferences; disabled service, no devices/shares |
| `en/es/assets/macs.png` | `e457e86` | Actual Linked Macs preferences; no connections/imports |
| `en/es/assets/updates.png` | `e457e86` | Actual update preferences; synthetic installed version, stable subscription, fake transport |
| `en/es/assets/activation.png` | `b8900bf` | Actual global activation dialog, synthetic source; copied byte-for-byte from `doc/validation/extension-recommendations/current/dialog-<locale>-global.png` |
| `en/es/assets/warnings.png` | `b8900bf` | Actual extension preferences/reset; copied byte-for-byte from `doc/validation/extension-recommendations/current/reset-<locale>.png` |

Full capture revisions:
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
Source `e457e86`'s production UI files are unchanged in this help-only continuation;
only guide selection/resources, editorial content, test harness and governance
change. Keep the original capture revision when reusing instructional assets.
For changed UI, recapture and replace both locales with new canonical metadata.
