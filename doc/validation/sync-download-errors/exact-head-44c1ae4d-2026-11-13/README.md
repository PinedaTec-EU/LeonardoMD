# PR #369 native error dialog captures

These screenshots were produced by the exact-source test `PeerSyncErrorMessageTests.testCaptureProductionDownloadAlert` from source commit `44c1ae4d6ddc17af5dda791eb45b3a0036a78157`. The test hosts the production macOS `DesktopPeerPreferencesView` in an AppKit window and injects a synthetic HTTP 413 corpus-size failure. The synthetic body uses the example path `docs/image.png` and quantities only.

The composed native window measures 600 × 532 points and the original PNG files are 1200 × 1064 pixels. Each screenshot has an observed context file and a generated metadata sidecar. `build-inputs.json` records the compiler-bearing command and Git tree IDs needed to verify that later evidence-only commits preserve the capture inputs.

This is a macOS desktop peer-sync capture. It does not represent the Little Leonardo iOS alert or satisfy TestFlight/physical-device acceptance for issue #380.
