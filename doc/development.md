# Development

For downloads and product usage, see the [README](../README.md).

## Build and run from source

Requires macOS 14 or later, Swift 6 / Xcode command-line tools, and Python 3 for packaging. From the repository root, run `./launch.sh`. This builds an optimized, locally signed app at `output/LeonardoMD.app` and opens it. A document path can be supplied as an argument. Run `swift test` separately for XCTest validation.

## Architecture and diagnostics

### Startup diagnostics

Startup emits JSON lines synchronously to stderr and at notice level to the macOS unified log under subsystem `eu.pinedatec.LeonardoMD`, category `startup`. Records include the phase, elapsed milliseconds, PID/parent PID, launch timestamp, bundle identifier/version/build, app-bundle status, OS and architecture. The activation-policy milestone records both the switch result and the actual policy (0 = regular, 1 = accessory, 2 = prohibited). Documents, full paths, command arguments and environment values are excluded. Missing bundle versions appear as `unknown`.

The `application_initializing` record is emitted before `NSApplication.shared`. If it is the last phase, inspect the crash stack and process-registration logs before blaming window or document code. Later milestones distinguish delegate setup, the event loop, menus, first-window construction and readiness. These breadcrumbs diagnose failures; they cannot recover from a framework abort. A stderr capture survives an abort even when the execution sandbox prevents unified-log delivery.

To inspect retained startup records, use Console with the subsystem/category above, or run:

```sh
/usr/bin/log show --last 15m --style compact --predicate 'subsystem == "eu.pinedatec.LeonardoMD" AND category == "startup"'
```

For ordinary local runs, use `./launch.sh`. For visual or fresh-process QA, use `./launch.sh --qa` from a normal GUI terminal and follow the [native QA launch checks](#native-qa-launches) below. A directly spawned AppKit executable inside an agent execution sandbox can abort during HIServices registration before creating a window. Compare the same binary outside that sandbox before changing product behavior. PID and launch timestamp distinguish diagnostic attempts from user sessions.

```sh
swift test
```

The package separates `LeonardoCore` (files/configuration/Git), `LeonardoRender` (WebKit and bundled engines) and `LeonardoApp` (macOS shell). The sample project in `Examples/Proyecto` exercises relative links, local images, diagrams, code, tables, metadata, tasks and mathematics.

Product stories are in [doc/US](US). The two presentation modes and opt-in engine policy are specified in [US.000016](US/us.000016.md) and [ADR 0001](adr/0001-native-macos-and-lazy-extensions.md). Delivery is tracked by [issue #1](https://github.com/PinedaTec-EU/LeonardoMD/issues/1).

The generated app is signed locally for development. Public distribution, notarization and other platform UIs require their own release workflow.

The application icon uses the approved Leonardo Classic folded-L artwork. Its original PNG and multi-resolution macOS ICNS are stored in `assets/AppIcon`; the packaging script includes the ICNS in the signed bundle for Finder and the Dock.

## Native QA launches

Use `./launch.sh --qa` to build and launch a disposable copy of the real app. The helper preserves the executable, resources and frameworks, gives the copy a unique bundle identity and re-signs it. Packaging rejects an incorrect executable or a direct XCTest dependency before launch. Run XCTest checks with `swift test`; never package `xctest` as a GUI app.

The command prints the temporary bundle path. Existing LeonardoMD instances keep product-wide single-instance ownership; a forwarded launch does not verify fresh startup. Confirm a new PID and `application_ready` startup records before claiming a fresh-process pass. Quit your existing app normally first when you want a separate startup check. Remove the printed temporary directory only after its QA process has finished.

For preparation without launch, run `python3 scripts/qa-bundle.py output/LeonardoMD.app` after packaging. Tracking: [issue #80](https://github.com/PinedaTec-EU/LeonardoMD/issues/80).

## Distribution and versioning

Local development signing does not establish public distribution acceptance. Follow [signed release preparation](releases.md) for Developer ID signing, Apple notarization, archive verification and publication gates. The [release ledger workflow](release-version-ledger.md) defines version allocation and compilation accounting; its historical baseline is not the latest published version. See [GitHub Releases](https://github.com/PinedaTec-EU/LeonardoMD/releases) for published packages.

For translations and resource maintenance, see [localization](localization.md).

The mobile companion is read-only. Desktop direct synchronization and system Git remain separate; the former proprietary mobile Git target is retired. See [legacy corpus recovery](mobile/git-retirement.md).
