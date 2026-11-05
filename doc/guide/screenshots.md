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
| `en/es/assets/updates.png` | `e457e86` | Actual update preferences; synthetic installed version, stable subscription, fake transport |
| `en/es/assets/activation.png` | `b8900bf` | Actual global activation dialog, synthetic source; copied byte-for-byte from `doc/validation/extension-recommendations/current/dialog-<locale>-global.png` |
| `en/es/assets/warnings.png` | `b8900bf` | Actual extension preferences/reset; copied byte-for-byte from `doc/validation/extension-recommendations/current/reset-<locale>.png` |

Full capture revisions:
- `f1ecf7b`: `f1ecf7b30cfacd296926b102a546402334a0cb67`.
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
