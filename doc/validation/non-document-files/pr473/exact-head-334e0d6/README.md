# PR #473 iOS evidence — source `334e0d6`

This capture set was collected from PR source commit
`334e0d6d55518a827ead653bfcbe72b4f3e451e6`, PR build delta 38. The app was
Little Leonardo 0.3.1889 on the already-booted iPhone 17 simulator
(`691F22BD-BD95-40DC-8744-352846B25B84`, iOS 27.0). The UI capture records the
simulator process and source SHA in each metadata sidecar.

## Captures

- `ios-settings-off.jpg`: the new preference is visibly off by default.
- `ios-settings-on.jpg`: the preference was toggled on; the runtime snapshot
  reported value `1`. It was then toggled back off and the runtime snapshot
  reported value `0`.
- `ios-mdlr-reader-es.jpg`: bundled `Demo-es.mdlr` opened in Little Leonardo.
- `ios-mdlr-assets-es.jpg`: the Markdown table and bundled local image render
  while non-document file rows remain hidden.
- `ios-mdlr-math-chart-es.jpg`: Mermaid, inline/display math, tagged
  box-counting equation `(1)`, and local chart render in the `.mdlr` reader.
- `ios-mdlr-practice-form-es.jpg`: the Spanish practice form is visible before
  entry with empty synthetic fields.

The simulator had no synchronized Mac project, so these visual captures do not
show an image file row from a remote catalogue. Shared filtering behavior and
surface-specific supported extensions are covered by
`LeonardoProjectFileVisibilityTests` and `DownloadViewsNavigationTests`; exact
head CI remains the authoritative automated gate. The practice save/reopen
flow is also covered by `MobileDemoUITests` and must be included in the exact
head CI result.

## Instance teardown and data state

XcodeBuildMCP launched Little Leonardo as PID `66575`; its first window showed
the library and the bundled Demo. `stop_app_sim` succeeded after capture. The
simulator was not shut down because this task did not boot it.

`install_app_sim` changed the app data-container UUID from
`1F9A520F-446A-43A9-B02E-237D784FD620` to
`2041D7B4-152F-4A53-9F85-A2C519077E24`; the old container was absent after the
install. A copy of the preferences plist was made before UI interaction and
restored byte-for-byte afterward (SHA-256
`29a3cb7ba8d2f5993221ebe1509bee5a3f408c8f3d79053e5b95c841f699e731`). The
Demo practice file used for capture matched its pre-test copy byte-for-byte.
No field was edited or saved during this visual pass. The prior container's
other app data could not be verified after installation.

The macOS packaged-app Help/practice acceptance is not represented here. The
active macOS QA process belonged to another task and did not include this PR's
preference; its owner elected to close it manually before a fresh current-source
macOS capture can proceed. Historical screenshots under `exact-head-a357/`
remain historical and are not current-head evidence.
