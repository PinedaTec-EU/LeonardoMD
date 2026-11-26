# PR #471 macOS QA on 2026-11-26

The real packaged app from source `42f2ee1e22cf92184556f300256acd4654113d57`
passed packaging validation. The compilation recorder recorded build delta 67.
The QA app ran version 0.3.2318, build 2318, in a disposable profile and
opened the synthetic local project's first window. The root, nested files,
selected-row mark and count were visible in the project tree.

English and Spanish Guide v149 opened from Help/Ayuda in this recorded run. The native document
showed the updated chapter 8 instructions for selection, moves, Option-copy,
and root, empty-space and file-row targets. The disposable personal copies
matched their bundled files byte for byte.

| Locale | SHA-256 |
| --- | --- |
| EN | `9b82261833538bf8afeae3dd1ca02e8b3b4d50808a0d093a35047e9c1e1484c1` |
| ES | `f7b0f5d0e49cf7852f32307cf8047b7c9bf96ee8dbcb9708efccacc37221b78f` |

The later reconciliation advances the packaged resource and personal-copy
directory to Guide v160 without claiming a new GUI run: EN
`03aeef497d89f20826bf689c106064f26b7968371c39b9fe340ad6bcd4702241`, ES
`2e165b15744ae41e7080bdf9808fa9554cb3eedff1d5d571d5a34f742d861729`.

The subsequent rebase onto `031bcea28e1a82c4f65d76efe60f57e1bea83e73`
retains this v160 native-equivalence record and advances only the bundled
resource to v163; no native repetition is claimed.

CUA's coordinate drag returned `noWindowsAvailable` and
`windowNotFoundAtPosition` on two displays. The fixture tree was unchanged.
This run establishes startup and bilingual Help. The native drop-target
outcomes still require a successful gesture. Prior native basic move and
Option-copy are documented on [issue #261](https://github.com/PinedaTec-EU/LeonardoMD/issues/261).

QA process PID 19896 started at 10:17:10 CET from
`/private/tmp/leonardo-471-native.gp0Wdd/tmp/leonardo-native-qa-tersrfcn/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`.
The application received its normal Quit shortcut and the exact PID was
subsequently absent. No simulator or Device Hub session was created.
