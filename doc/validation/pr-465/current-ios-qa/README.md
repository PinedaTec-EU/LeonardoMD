# Current-head iOS QA

Date: 2026-11-26 (CET)

This evidence was captured from the reconciled candidate at commit
`fd7b8b116f36e2bec360ffccecf2d0992387a3cd`, based on
`origin/main` `32efc6f211380c91944f17873993af27e406b67a`. The app was built
from the isolated worktree with the repository recorder and installed without
rebuilding during the visual run:

```text
build product: .build/recorder-ios/Build/Products/Debug-iphonesimulator/LittleLeonardo.app
XcodeBuildMCP profile: pr465-ios-qa
project: Mobile/LittleLeonardo.xcodeproj
scheme: LittleLeonardo
simulator: iPhone 17, iOS 27.0
UDID: 691F22BD-BD95-40DC-8744-352846B25B84
bundle: eu.pinedatec.LittleLeonardo
```

The preflight found the selected simulator shut down and no Little Leonardo
process. The task created app process `85795` at 09:45:23 CET and later
process `95369` at 09:53:25 CET; `stop_app_sim` succeeded for both and `ps`
confirmed that neither remained. The focused test host (`96272`) also exited.
The task booted only the selected simulator and shut it down after evidence;
`simctl list devices` confirmed it was `Shutdown` at teardown. Other simulator
and app processes were not touched.

## Native flow

1. Opened **Library → Sync settings → Document extensions**. All five
   device-local switches were independently enabled and the settings screen
   remained responsive.
2. Opened **Library → Demo, Local → Demo-en.mdlr · English**. The earlier
   all-disabled state displayed the grouped consent recommendation; selecting
   Mermaid and Math dismissed it. The remaining three switches were then
   enabled in Sync settings and the English Demo reopened without a second
   recommendation.
3. Scrolled the English Demo through its instructions, read-only/offline copy,
   Markdown formatting and callout content. The rendered page remained stable.
4. Opened **Sync settings → Acerca de Little Leonardo → Ayuda**. The native
   Help page rendered its Spanish headings and bilingual Spanish/English copy,
   including the current frequency and document-extension guidance.

The runtime logs captured by XcodeBuildMCP reported no crash or failed launch.
They contain the simulator's WebKit duplicate accessibility-class warning and
`NSMapGet ... map table argument is NULL`; both were non-fatal. Canonical log
paths:

```text
~/Library/Developer/XcodeBuildMCP/workspaces/LeonardoMD-586d26453937/logs/eu.pinedatec.LittleLeonardo_2026-11-26T08-45-23-191Z_helperpid85784_ownerpid16571_15c6d47d.log
~/Library/Developer/XcodeBuildMCP/workspaces/LeonardoMD-586d26453937/logs/eu.pinedatec.LittleLeonardo_2026-11-26T08-53-25-086Z_helperpid95360_ownerpid16571_66201c34.log
```

## Captures

All PNG captures are native Simulator screenshots at 1206 × 2622 pixels.

| Capture | Assertion | SHA-256 |
| --- | --- | --- |
| [Extension settings](extension-settings-all-enabled.png) | All five extension switches on after independent changes. | `5060eea71e7ccc138044164d1d26b83ddfc4a1ee2b936c15a221d8cdecd1b243` |
| [English Demo](demo-en-all-enabled-top.png) | Bundled offline English Demo opens with all five extensions enabled. | `71b80e8636f621beb1f1edeee5dc7582c899b8641117939343f81449eff0bd6c` |
| [English Demo scrolled](demo-en-scrolled.png) | Read-only/offline instructions, Markdown formatting and callout remain rendered while scrolling. | `26f4df5702ebe79a567c4eb7be6fe6f152c0d8e0e24daadee9d3ab312d46f3a8` |
| [Spanish Help](help-es-top.png) | Native Help route opens and renders the bundled bilingual guidance. | `450512768fac872ec8edf342e1c1f4b161ecf2c0ad99a4a27854387e398ca0a7` |
| [Spanish Help extensions](help-es-extensions.png) | Current frequency and document-extension guidance is visible in the native Help view. | `f183e6a75e1d3a2493fe4d39633f0ee6c74f04b8a7ed60c942cec7a983b38f3a` |

`library.png` (`4a21c0159231519550440624893d29cb97492a36f16488eba67ef376bc2bccc4`)
is retained as the Library route context.

## Automated checks

- `python3 -m unittest scripts.tests.test_package_user_guide`: 3 passed.
- Generic iOS compilation through `scripts/compile-and-record.py`: passed,
  build delta 18.
- Focused iOS Simulator tests through the recorder:
  `MobileDemoStoreTests` (9 passed) and `MobileExtensionRecommendationsTests`
  (2 passed), 11 passed / 0 failures, build delta 19.
- The regenerated Guide v147 packages used by the candidate are EN
  `69b9811c51634422a15a1a2ea0203ab21d0ed5b7ab5f10745260537a2b401a82` and ES
  `da3d046493102110c33bf334fdb707bcd1833231ca881dcb84dd71d9b88ea45a`.

Physical-device/TestFlight acceptance and the coordinator's fresh judge remain
separate gates; no merge was performed.
