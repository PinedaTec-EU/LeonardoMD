# PR #428 native status evidence — Guide v67 candidate

This bundle records the exact-source native preference component states and
the packaged bilingual Help smoke for the current #428 candidate.

## Native synchronization status captures

| State | Image | Sidecar | Capture |
|---|---|---|---|
| Helper health check in progress | [status-checking.png](status-checking.png) | [metadata](status-checking.metadata.json) | 2026-11-13 00:22:32 UTC |
| Confirmed online | [status-online.png](status-online.png) | [metadata](status-online.metadata.json) | 2026-11-13 00:22:32 UTC |

Both captures show the production SwiftUI synchronization component hosted in
native AppKit, at `/native/preferences/synchronization`, with synthetic state.
The 532 × 260 native-point viewport produced 1064 × 520 PNGs on macOS 27.0.1.
There is no browser engine or CSS viewport. The two images have the same
SHA-256 (`3d3505854df2f47ae898a58f1ed03d83ce21a8e78728366d1718f3a8609e480f`):
the retained green status and layout are intentionally identical during a
check and after confirmed recovery.

The component source is commit
`964f5fc260b5e2f14f13d44e53d0b6a14a36faaa`. The screenshot sidecars bind that
revision and the original capture times. At collection, the only tracked
worktree change was the #428 compilation ledger entry (`build` 196 → 197);
the untracked files were this capture bundle. No product source or UI input
changed after the capture-source commit. The captures do not depict the
provisional consent-poll alert; its recovery behavior is covered by the
controller regression test.

## Packaged bilingual Help smoke

- App instance: `eu.pinedatec.LeonardoMD.qa.de36111eae6f41fd8b3da8fb9166ff27`
- Isolated profile: `/tmp/LeonardoMD-QA-428-v67-VDlZiJ`
- Displayed app version/build: `0.3.1339` / `1339`; bundled guide revision: `v67`.
- Opened English and Spanish guides from the real Help menu in this packaged
  app instance. Checked the rendered Mermaid diagram, inline and one-line math,
  multiline display equations with underscored variables and underbraces, the
  tagged box-counting equation `(1)`, charts, local images and tables. With Math
  off, notation fell back to source and code examples remained literal; with
  Math on, the equations rendered without literal delimiters or KaTeX errors.
- Filled each separate practice form with fictional values, saved, closed, and
  reopened it from its guide. The Spanish responses were rechecked after
  reopening: `Muestra QA`, `Documento ficticio de aceptación.` and the checked
  “Listo para compartir” box. The English practice form was also reopened with
  its fictional test values intact.

The guide archives in the isolated profile are byte-identical to the v67
archives in the candidate app bundle:

| Locale | SHA-256 |
|---|---|
| English | `11019f6b4bce83b981c7964bc80699980253b08179623376cd47aed34d5694d4` |
| Spanish | `577e41514390a9b1f6a67a341846b9e167a4771f798d37961ffbc770a572969d` |

The isolated practice-file hashes after the round trip were English
`8a4c33d42f90db21690e6525e61dc76571a6fcf18b5a28b6469d964813d1e80d` and
Spanish `e7ad4288e40765cdfb17f2194da52a8bfbb8976f937719c761b0792ed16890db`.
They contain only the fictional QA responses and do not replace the bundled
templates.

This smoke verifies the packaged Help flow and working-copy persistence in the
identified instance. It does not establish fresh-process readiness, signed
live-helper acceptance, hosted beta installation/update/relaunch, or physical
two-Mac acceptance; those remain pending.
