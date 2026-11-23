# Illustrated Preferences macOS QA

[Issue #575](https://github.com/PinedaTec-EU/LeonardoMD/issues/575) · [PR #576](https://github.com/PinedaTec-EU/LeonardoMD/pull/576)

Production and bundled-help source tested at `7e688537fedc969a686c903cf1be8fc2e0d400ba`. Subsequent changes record evidence and compilation counts.

## Scoped visual evidence

Four production SwiftUI pane captures use synthetic standalone settings in
Spanish, light theme, at 780 × 780 points. The capture harness ran through
XCTest on PR head `6a8245d7e00f2a547817310e7836f90d8bcec286`. The final
evidence commit changes the captures, report and compilation accounting.

- [General](preferences-general-es.png)
- [Extensions](preferences-extensions-es.png)
- [Synchronization with Share selected](preferences-sync-es.png)
- [Updates](preferences-updates-es.png)

The [Remote selector state](../../guide/es/assets/sync-connections-v125.png)
and the linked Mac's expanded detail below cover the alternate synchronization
state. The guide checks are recorded as separate regression results.

## Native evidence

- Route: LeonardoMD → Preferences → General, Extensions, Synchronization and Updates. The first packaged instance showed the four illustrated headers at 780 × 780 points and exposed the English and Spanish role buttons. Switching to Remote exposed its scrollable device workspace. The preview used Leonardo Classic. No real device was paired or refreshed for QA.
- [Share in Spanish](../../guide/es/assets/sync-sharing-v125.png) and [Remote in Spanish](../../guide/es/assets/sync-connections-v125.png) show the production role selector in an isolated fixture. [Share in English](../../guide/en/assets/sync-sharing-v125.png) and [Remote in English](../../guide/en/assets/sync-connections-v125.png) show the same states.
- [Light](remote-project-review-light.png) and [dark](remote-project-review-dark.png) show a synthetic Mac expanded in the production remote projects component at 600 × 460 points. These are native component captures, not full-window dark-mode acceptance.
- `LEONARDO_SOURCE_PR=576 ./launch.sh --qa` launched two distinct QA app processes with the real LeonardoMD executable and Sparkle. No LeonardoMD process existed before either launch. PIDs 92609 (guide v124) and 96491 (guide v125) both started a first window on macOS 27.2.1, candidate base 0.3.2189. Their disposable bundle directories were `leonardo-native-qa-ci6sfobj` and `leonardo-native-qa-zieagszv`, respectively. Both were quit normally, and the exact PIDs were verified absent. No device sessions were opened.

## Bilingual help

Both v125 personal copies opened through the actual Help menu and matched the bundled packages byte for byte.

- en SHA-256 `f4ad9fa310080c288b339e4514da4eec081370b362eb3c319a6685966f387a69`
- es SHA-256 `d93dbab7e0a5f79769fc419645d6afb0152fa241d470aeb9186ddf20cb525658`

Both practice links opened in LeonardoMD. Fictional answers were saved in disposable copies outside the existing personal forms, then reopened in the v125 QA instance and confirmed in their fields. The native WKWebView tests exercised the bundled images, Mermaid, charts, tagged KaTeX display formulas, literal source and tables across both locales. Complete on-screen inspection of all live examples and disabled-extension fallback remains pending, as does hosted beta install/relaunch acceptance.

## Checks

- Nine focused Swift XCTest cases passed across bundled help and DesktopPeer native acceptance.
- Three deterministic user-guide packaging tests and seven compilation-recorder tests passed.
