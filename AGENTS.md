# Agent Instructions

<!-- ai-skills-bootstrap:begin -->
## Shared skills

Read `.skills/index.md` to discover the shared skills selected for this repository.
Load only the adapter relevant to the current task.
Canonical source: `../ai-skills-shared`.
<!-- ai-skills-bootstrap:end -->

## Release progression

For macOS release preparation, publication or promotion, use the repository-local
[leonardo-release skill](.skills/leonardo-release/SKILL.md). The normal progression
is accepted PR → published and validated beta → stable. Only an explicit owner
instruction for the candidate may skip beta; the skill records that exception
without waiving the remaining delivery and distribution gates.

## Native macOS QA launch convention

Prevent the temporary QA startup failure tracked in [issue #80](https://github.com/PinedaTec-EU/LeonardoMD/issues/80):

- Run XCTest checks through `swift test` or the project's configured `xcodebuild test` workflow. Never place `xctest`, an XCTest runner, or a test executable inside an `.app` and launch it as a standalone GUI application.
- For visual QA, use `./launch.sh --qa` (delegates to `scripts/build-app.sh` and `scripts/qa-bundle.py`) to produce the real `LeonardoMD` executable with its packaged resources and frameworks. A disposable QA copy must preserve that executable and its dependencies; only adjust bundle identity/display metadata as needed and re-sign after changes. A separate bundle identity does not bypass LeonardoMD's product-wide single-instance ownership; respect the existing instance workflow and do not terminate the user's running app without authorization.
- Before launching a disposable QA bundle, check that `CFBundleExecutable` names the real app executable and inspect its dependencies with `otool -L`. Reject a standalone GUI launch if it links `XCTest.framework`; correct the executable or use the test runner. Do not mask this packaging error by copying XCTest into the app or adding machine-specific Xcode framework search paths.
- Validate a fresh process and actual first-window readiness. A successful build or launch-command exit is insufficient; forwarding to an existing instance does not prove startup. If single-instance ownership prevents a fresh-process check, record that validation limitation.
- If launch fails, retain the crash signature, bundle identity, available version/build, executable identity, launch method and startup logs in the canonical GitHub issue. Distinguish temporary QA failures from crashes of the packaged product and group recurrences by failure signature.

This is a preventive agent workflow rule; documenting it alone does not resolve issue #80 or establish that the original QA generator has been repaired.

## Close task-owned QA instances after testing

The lifecycle correction tracked in [issue #438](https://github.com/PinedaTec-EU/LeonardoMD/issues/438)
applies to LeonardoMD and Device Hub validation for every issue:

- Before launching, record the existing app processes and device sessions. Track
  each instance created by this task using PID, start time and executable/bundle
  path; for Device Hub also record session/device identifier and app identifier.
  A familiar app name or QA bundle identifier alone does not establish ownership.
- After collecting the required evidence (including both bundled-help smoke
  tests), gracefully quit every app instance created by this task. Close each
  Device Hub session opened by this task and stop its test app. Shut down a
  simulator only if this task booted it and no other task now uses it; never
  shut down or erase a physical device as cleanup.
- Perform teardown after successful, failed or cancelled validation, before
  handing off or closing the issue. If interrupted before cleanup, reconcile
  the recorded identities and finish cleanup when work resumes.
- Verify the exact processes have exited and the owned Device Hub sessions have
  closed. Record the identities and teardown result in the canonical issue/PR.
  A quit request or closing a viewer window alone is not proof of termination.
- Preserve pre-existing/user-owned/other-task instances. Never use name-wide
  kill commands or blanket device shutdown. If ownership is ambiguous, a quit
  prompts about unsaved work, or the required control tool is unavailable,
  report the retained identity and reason; do not force quit, discard work or
  claim cleanup succeeded.

## User help maintenance

PRs that add, remove or change a user-visible feature must update the Spanish
and English bundled help in the same PR. Apply the repository-local
[leonardo-user-guide skill](.skills/leonardo-user-guide/SKILL.md) for those
changes and when reviewing their help impact. Include relevant images/examples,
regenerate the packaged guides, and record validation in the PR. Internal changes
with no user-visible help impact must explain that conclusion in the PR.

## Mandatory help smoke test in tested instances

For every change or validation involving an app instance, open the bundled Spanish
and English user guides in that same instance through the real Help workflow.
Inspect the representative live examples: Mermaid, inline/display math, charts,
local images, tables and the separate practice form (open, fill, save, reopen).
Keep characteristic supported features represented in both guide sources.
Always inspect one-line and multiline `$$` formulas, Markdown-sensitive TeX
(underscores/underbraces), and the tagged box-counting equation from recurring
[bug #272](https://github.com/PinedaTec-EU/LeonardoMD/issues/272).
With Math enabled, require actual display equations and the equation tag, with
no KaTeX errors or literal delimiters; also check the disabled-extension fallback
and code examples staying literal. Record instance identity, build, locale,
extension state and evidence. XCTest/WKWebView component tests supplement this
check but do not replace opening help in the tested packaged application.
If no fresh instance can be tested, report that acceptance as pending.
