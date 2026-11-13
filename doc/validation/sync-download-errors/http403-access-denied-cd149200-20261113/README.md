# HTTP 403 access-denial alert with operation/status

Tracking: [#368](https://github.com/PinedaTec-EU/LeonardoMD/issues/368), [PR #369](https://github.com/PinedaTec-EU/LeonardoMD/pull/369).

The production `DesktopPeerPreferencesView` shows localized recovery text and,
when an HTTP 403 is known but its authorization cause remains unresolved, the
bounded reference `[LL1 op=file http=403]`. It preserves the operation and
status without claiming that the device or project was revoked. OCR verified
the localized recovery, operation, status and confirmation button in both
languages.

| Locale | Native window | Capture and metadata | SHA-256 |
|---|---:|---|---|
| English | 600 × 532 pt | [image](access-denied-en.png) · [metadata](access-denied-en.json) · [context](access-denied-en.context.json) | `26d81115b4484a41184905f710b880a7ce05f745c71810d6b90d7dc5b26973a7` |
| Spanish | 600 × 532 pt | [image](access-denied-es.png) · [metadata](access-denied-es.json) · [context](access-denied-es.context.json) | `596dca8614aecb14452dd6143df668b2bdca6d015447ec4ddfcb039941735d99` |

Both images are 1200 × 1064 px and use synthetic state with no device,
project, credential or document data. The opt-in AppKit/SwiftUI capture test
passed for both languages on source commit
`cd1492005e5178c5e7e7b87bf3a0e305b7ab2e18`. It ran with PR build delta 46;
the successful recorder advanced the ledger to 47 in commit
`6611db684b8f25513ffa8fe348cfb9a48ff583db`, which changes only that counter.
See [build-inputs.json](build-inputs.json) for the tree bindings and command.

The former [status-only capture set](../http403-access-denied-caf23aeb-20261113/README.md)
remains as history. These are desktop synchronization captures, not Little
Leonardo simulator, physical-device or TestFlight acceptance.
