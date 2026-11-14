# PR #445: Little Leonardo host display name

## Reviewed build and capture

- Application source/build: `d171714b7eeffc1d32ffd243abb0cc403f338f19` (`codex/442-ll-host-display-name`). The Little Leonardo iOS Simulator build and launch completed from this worktree.
- The current PR head `34d7a8962e7b9e32008724f7fc200cdf646e0ab0` adds only evidence files; no application or guide source changed between the build and capture.
- Project and scheme: `Mobile/LittleLeonardo.xcodeproj`, `LittleLeonardo`, Debug.
- Device: iPhone 18 Pro Max Simulator, iOS 27.0, UDID `2E154439-376B-4771-A52D-5A46A11F96B9`.
- Screen: native `Biblioteca`, remote Mac expanded with a pending incoming project.
- Browser: not applicable; SwiftUI native app. The screenshot tool reported a native frame of 368 × 800 px; CSS viewport dimensions do not apply.
- Data: synthetic. `Mac QA` is the locally renamed alias; `Proyecto nuevo` is a pending QA project, with **Añadir** and **Ignorar** visible. The local Demo is present, so the local section correctly appears with content.
- Screenshot: [library-incoming-project.jpg](library-incoming-project.jpg). Its capture context and SHA-256 sidecar are in [library-incoming-project.context.json](library-incoming-project.context.json) and [library-incoming-project.metadata.json](library-incoming-project.metadata.json).

## Validation

- `MobileConnectionDisplayNameTests`: 4 passed, 0 failed. This includes fallback/legacy decoding, hostname suggestion, rename persistence across asynchronous reload and relaunch, and preserving connection identity/grants.
- `build_run_sim` succeeded on the exact application source SHA above.
- Current code-head CI: [macOS MVP run 43548903891](https://github.com/PinedaTec-EU/LeonardoMD/actions/runs/43548903891) and [run 43548899633](https://github.com/PinedaTec-EU/LeonardoMD/actions/runs/43548899633).
- The PR still requires the packaged LeonardoMD Guide v79 Spanish/English Help smoke and a fresh strict independent judge before merge. These remain pending until their evidence is attached.

## Reproducing the native screen

Use XcodeBuildMCP with the project and scheme above, iPhone 18 Pro Max on iOS 27.0, and call `build_run_sim`. Open `Biblioteca`; the simulator used for this capture already has the synthetic paired-host and pending-project fixture. No browser route exists for this native screen. For a clean simulator, pair with a QA Mac that shares a new project, rename the connection, then expand the host; do not use production content.
