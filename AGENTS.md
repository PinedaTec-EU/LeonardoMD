# Agent Instructions

<!-- ai-skills-bootstrap:begin -->
## Shared skills

Read `.skills/index.md` to discover the shared skills selected for this repository.
Load only the adapter relevant to the current task.
Canonical source: `../ai-skills-shared`.
<!-- ai-skills-bootstrap:end -->

## Native macOS QA launch convention

Prevent the temporary QA startup failure tracked in [issue #80](https://github.com/PinedaTec-EU/LeonardoMD/issues/80):

- Run XCTest checks through `swift test` or the project's configured `xcodebuild test` workflow. Never place `xctest`, an XCTest runner, or a test executable inside an `.app` and launch it as a standalone GUI application.
- For visual QA, use `./launch.sh --qa` (delegates to `scripts/build-app.sh` and `scripts/qa-bundle.py`) to produce the real `LeonardoMD` executable with its packaged resources and frameworks. A disposable QA copy must preserve that executable and its dependencies; only adjust bundle identity/display metadata as needed and re-sign after changes. A separate bundle identity does not bypass LeonardoMD's product-wide single-instance ownership; respect the existing instance workflow and do not terminate the user's running app without authorization.
- Before launching a disposable QA bundle, check that `CFBundleExecutable` names the real app executable and inspect its dependencies with `otool -L`. Reject a standalone GUI launch if it links `XCTest.framework`; correct the executable or use the test runner. Do not mask this packaging error by copying XCTest into the app or adding machine-specific Xcode framework search paths.
- Validate a fresh process and actual first-window readiness. A successful build or launch-command exit is insufficient; forwarding to an existing instance does not prove startup. If single-instance ownership prevents a fresh-process check, record that validation limitation.
- If launch fails, retain the crash signature, bundle identity, available version/build, executable identity, launch method and startup logs in the canonical GitHub issue. Distinguish temporary QA failures from crashes of the packaged product and group recurrences by failure signature.

This is a preventive agent workflow rule; documenting it alone does not resolve issue #80 or establish that the original QA generator has been repaired.
