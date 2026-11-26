# Home recovery and Guide v150 native QA

Tracking: [PR #516](https://github.com/PinedaTec-EU/LeonardoMD/pull/516) and
[#514](https://github.com/PinedaTec-EU/LeonardoMD/issues/514).

## Packaged process

The candidate was built from source `017636506dbdfc6f12df7c5330e47b659b567a08`
with `LEONARDO_SOURCE_PR=516 ./scripts/build-app.sh`. The package reported
version `0.3.2307`, build `2307`, and the successful compilation ledger recorded
delta 15. The QA bundle was the real `LeonardoMD` executable at
`/var/folders/_s/khfztzr97kd4049py5k3zsg80000gn/T/leonardo-native-qa-80p8igvh/LeonardoMDQA.app`.
Startup reached `application_ready` in fresh process PID `32201`; the bundle
had no XCTest linkage and used the disposable home
`/tmp/leonardo-516-qa.gajRv4/home`.

The fixture contained only synthetic folders. No user project was opened or
modified, and no real Sync grant, pairing, helper or preference was changed.

## Home relocation flow

| State | Native result |
| --- | --- |
| Fresh Home | No saved items; the synthetic project was opened through `Open project…`, producing a Recent row for `Old Project`. |
| Missing saved location | After the fixture folder was moved, the row became disabled and showed the checked old path plus the warning that the saved location was not found. Its warning menu exposed `Retry saved location` and `Locate moved item…`. |
| Intentional cancel | `Locate moved item…` opened the native folder chooser. `Cancel` left the row disabled and preserved the old path. |
| Successful recovery | Choosing the synthetic `New Project` folder and `Use this location` changed the row to an enabled `New Project` at `/private/tmp/leonardo-516-qa.gajRv4/New Project`; opening it displayed the expected `README.md` and `relocation-note.md`. |

## Bundled Help smoke

Help was opened through the application Help menu in both languages. The
working copies were created in the disposable home and their hashes matched
the candidate package:

| Locale | Working copy opened by Help | SHA-256 | Native checks |
| --- | --- | --- | --- |
| English | `.../User Guides/v150/en/Guide-v150-en.mdlz` | `5a1f977777180d52b40d5d577b7f212fcc7b120b54bf98dab1dde6d3edb7fd83` | Package header showed `en`; chapter **7. Home, recent items and favorites** rendered and described `Locate moved item…`. |
| Español | `.../User Guides/v150/es/Guide-v150-es.mdlz` | `22c7954087c889d48faa6e3b5acb00643ecfa1e68b87df7a1c7ec119a03ac197` | Preferences changed language only inside the disposable home; Help reopened as `es`; chapter **7. Inicio, recientes y favoritos** rendered and described `Localizar el elemento…`. |

The extension recommendation was dismissed with `Not now/Ahora no`; no
extension or synchronization setting was enabled. The practice form was not
re-run because this PR changes Home recovery and bundled Help packaging, not
practice behavior; deterministic guide/package tests cover the packaged
resources.

After the final Help check, the QA app was quit through its native application
menu. A process check found no remaining `LeonardoMDQA.app` or task-owned
`LeonardoSyncHelper` process. The synthetic fixture and isolated package were
left intact for hash and audit reproduction.
