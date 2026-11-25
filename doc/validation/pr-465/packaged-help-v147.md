# Packaged Guide v147 Help smoke

Packaged source: `162d8b089375ad4a6fae7962cf7d67d0d2463ac2`. Build reported `0.3.2307 / 2307`. Launch used `LEONARDO_SOURCE_PR=465 ./launch.sh --qa`, the real `LeonardoMD` executable and dependency verification without XCTest linkage. The recorder captured the successful packaging compilation as PR build delta 17.

| Locale | Native route and rendered content | SHA-256 of both the Help-created copy and bundled resource |
| --- | --- | --- |
| English | Help → Leonardo user guide, Built-in extensions on iPhone and iPad | `2dc961c482eb7443b499824c2ab1782a68d1dfdfa84d12bc0a6b2b30202a4cc3` |
| Spanish | Ayuda → Guía de Leonardo, Extensiones incluidas en iPhone y iPad | `c9aea2d1e54cb1bbd3b504a5a3e7d0d0d26efab92a30d79b0b0cfda1dcdef875` |

Both passes used disposable homes and verified local settings, read-only received documents, the Demo consent flow and the on-demand/offline scope. Three deterministic package checks passed. The mobile interaction and simulator validation of the revised candidate remain separate.

All processes below ran on 2026-11-26 CET from `leonardo-native-qa-t9bq21to/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`, bundle `eu.pinedatec.LeonardoMD.qa.22f64a64e6374040bbda6403e558ffcf`.

| Owned PID | Start | Result |
| --- | --- | --- |
| 20794 | 00:49:13 | Initial QA launch restored a pre-existing Guide v146. Excluded from the v147 evidence. It quit normally and its exit was verified. |
| 21510 | 00:50:19 | English Help in a disposable home. It quit normally and its exit was verified. |
| 22175 | 00:51:10 | Spanish Help in a disposable home. It quit normally and its exit was verified. |

This pass opened zero Device Hub sessions, devices or simulators.
