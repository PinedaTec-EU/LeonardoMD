# PR #473 packaged macOS validation

Capture date: 2026-11-19 (Europe/Madrid)

## Instance and source

- App: LeonardoMD QA `0.3.1894` / build `1894`.
- macOS: `27.0.1` (`26A434`).
- Bundle ID: `eu.pinedatec.LeonardoMD.qa.c7b6827910e142988334a39e824990ea`.
- QA process: PID `31297`, launched with `LEONARDO_SOURCE_PR=473 ./launch.sh --qa .build/pr473-visibility-sample`.
- Product code under inspection: `6c31b8f3d054779f0dd917b67d21e36a57bfc797`. The PR head at capture time was `7d0786699f21901078873d7e16c6a0925d58014e`. Later history rebases the PR and corrects CI fixture setup; the captured macOS product code is unchanged.
- The sample project and practice-answer files used synthetic content.

## Preference and project listing

The first-run preference was **off**. With it off, the project list omitted the synthetic image file while the Markdown image stayed rendered. With the preference on, the non-document rows appeared. The settings and file-list captures are from the packaged QA app.

The three display captures below were cropped at the bottom to remove the desktop account label; the preference controls and file rows remain visible.

| Capture | State | SHA-256 |
| --- | --- | --- |
| `macos-preferences-off.png` | Initial default, off | `121f5c69ba6a2607bec20a97a95a2c876052a04d376ba748bdf630bac7fcf405` |
| `macos-preferences-on.png` | Preference enabled | `9f4efcaa307fe5a197c0bc59bec6e50a25e408f8fe31f184bdaf0adb2088a5f6` |
| `macos-files-on.png` | Synthetic `.json` and `.txt` rows visible | `d76d4bd77bad372061482f6dda8de2586d547fc8c77a5f68533eecf4ed94a770` |
| `macos-image-row-hidden-image-visible.png` | Image row hidden; Markdown image still visible | `6874ce38099fcca536cca81eb8d1f0ade48833ff48d83ee7a42e8ee5bb54fd10` |
| `macos-image-row-visible.png` | Image row visible after enabling preference | `765c7e22f1b028f5e07973058c7830901f6b9d00c7ad3324c8f0e4dbc32fd534` |

## Bundled Help smoke

Both guides were opened through **Help → Leonardo User Guide** in the same packaged process. The English Help captures with Math enabled show Mermaid, inline and multiline `$$` formulas, Markdown-sensitive TeX, the tagged box-counting equation `(1)`, and charts. The Math-disabled capture shows the source notation as the fallback and fenced code examples stay literal. The Spanish guide capture shows the Spanish Help route; its practice section and field table are in a separate capture.

| Capture | Locale and extension state | SHA-256 |
| --- | --- | --- |
| `macos-help-en.png` | English Help entry | `005e219da14bc9454146aac209a87300c498620ce1d0dd1ef78cafab68e63f95` |
| `macos-help-en-mermaid.png` | English; Math and Charts enabled; Mermaid and inline/one-line formula | `493129fd786636fbc3346e9489a32261540bf8b6d7c6e8596cc095b3dda26a85` |
| `macos-help-en-tagged-equation.png` | English; Math and Charts enabled; display equation, tag `(1)`, charts | `8d0d5a8dfe5e86e0989ec1978d15276d7cde8733e362a4052addea9984c8dba1` |
| `macos-help-en-math-disabled.png` | English; Math disabled; raw TeX fallback | `b7f64d977139910b652bb89f71b4615c51496beeb6f15f894c2a5c4da8d1a186` |
| `macos-help-es.png` | Spanish Help entry | `95b197a813cdfd624e72c68e5ce952ba6b6169653c35f5c98c57769e12303f14` |
| `macos-help-es-practice-table.png` | Spanish practice instructions and field table | `fafeca8284e02189ba5413f8d66aa32801fd256c35d642713d6fcd998e82539c` |

The bundled Spanish practice resource was opened from the disposable QA bundle and a synthetic answer was saved for `macos-help-es-practice-saved.png` (`7bbbe7327614bf84fe0a618cfe1d609997f14135e3a6b0da25c3cad88d990263`). After capture, the resource was restored byte-for-byte to the repository source; both hashes were `787084bde360988264cbcdf389f1a2e0ac061d46657b5b92618bc827b76bf17d`.

The Help action also found an existing per-user practice copy. It was left untouched. A separate MDLR with a unique document ID opened in Fill mode, but this Mac run did **not** verify name/goal persistence after reopening. The independent Little Leonardo XCTest `testPracticeAnswerSavesAndReopensOffline` passed `1/1` in `.build/qa-pr473-practice-20261119.xcresult`; this is the save/reopen acceptance for the practice flow, not a Mac save/reopen claim.

## Teardown

The task-created Mac QA process (PID `31297`) exited after the app’s Quit command. XcodeBuildMCP stopped task-created Little Leonardo PID `33244`; a process check confirmed both had exited. The simulator was left booted.
