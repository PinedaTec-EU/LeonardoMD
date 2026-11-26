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

## Focused visual retake and process identity reconciliation

An authorized focused retake used the same packaged bundle and a synthetic
fixture only. Through the native Home window, CUA screenshots captured both
the disabled `Old Project (moved marker)` row with its warning menu (`Retry
saved location` / `Locate moved item…`) and the enabled `Old Project (visual
relocated)` row after choosing the moved folder. The project pane showed the
synthetic `README.md` and `relocation-note.md`. The retake used no user data,
projects, Sync grants or real preferences.

The final process reconciliation covered every exact-bundle PID present in
the durable startup logs or observed during the task:

| PID | Evidence and role | Final state |
| --- | --- | --- |
| `30766` | `app.log`, direct non-isolated startup at 01:00:20 CET; reached `application_ready` | Exact bundle absent at final check; quit method not attributed. |
| `32201` | `app-isolated.log`, valid isolated packaged QA at 01:02:03 CET; reached `application_ready` | Native application-menu quit was used for this isolated flow; exact bundle absent at final check. |
| `32723` | `app-envcheck.log`, environment-control process at 01:02:47 CET; no `application_ready` | Exact bundle absent at final check; quit method not attributed. |
| `33207` | Coordinator `ps` observation at 01:03:29 CET; no durable startup log or launch command | Exact bundle absent at final check; provenance and quit method unknown, so neither is claimed. |
| `36725` | Coordinator `ps` observation at 01:07:16 CET; no durable startup log or launch command | Exact bundle absent at final check; provenance and quit method unknown, so neither is claimed. |
| `39722` | Exact-bundle `ps` observation at 01:09:12 CET after a CUA rebind; no durable startup log | Exact bundle absent at final check; provenance and quit method not attributed. |
| `43997` | Focused visual retake launched at 01:15:23 CET with the isolated `open -n -a` flow; native Home window reached | Native application-menu quit issued; exact PID and bundle/helper absence verified at 01:19:53 CET. |

No `LeonardoMDQA.app` process or task-owned `LeonardoSyncHelper` remained at
the final exact-path check. The synthetic fixtures and isolated package were
left intact for hash and audit reproduction.
