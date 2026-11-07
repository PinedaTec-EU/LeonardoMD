# Project identity in macOS and iOS

Tracking: [#399](https://github.com/PinedaTec-EU/LeonardoMD/issues/399), [PR #400](https://github.com/PinedaTec-EU/LeonardoMD/pull/400).

`LeonardoCore.ProjectIdentity` owns the common symbol and bilingual role vocabulary.
The symbol is `square.stack.3d.up`; ordinary child folders retain `folder`.

| Viewed from this device | Indicator | Meaning |
| --- | --- | --- |
| Local | None | Locally owned project without configured outward sharing |
| Shared from this device | `person.2` | Local project configured as an outgoing shared source |
| Received from another device | `network` | Incoming content; sharing by the source is already implicit |

Never add an outgoing-sharing badge just because incoming content is shared by
its source. Offline cache storage does not change a received project's origin.
Recovery archives have a separate description with no remote indicator. Unknown
metadata displays a neutral project identity rather than an invented local role.

`DesktopProjectPresentation` derives macOS roles from configured source roots and
authorized `DesktopPeerController.copies`. A managed cache path without a known
copy stays unknown. Receiving wins over a stale outgoing-source entry. Source
selection scope and paused/unavailable sharing are displayed separately.

`ProjectIdentityLabel` and its small native icon adapter serve macOS headers and
project lists; `RecentItemsMenu` uses the same symbols and keeps parent paths for
disambiguation. `MobileProjectIdentityLabel` uses the same contract for iOS
library/detail rows: direct projects are received, legacy Git payloads are recovery
archives. No new iOS creation, sharing or onward-sharing capability is introduced.

The bilingual project/synchronization help explains the same-project source and
recipient example, partial sharing and offline behavior. See
`doc/guide/feature-coverage.md` for the maintained help entry.
