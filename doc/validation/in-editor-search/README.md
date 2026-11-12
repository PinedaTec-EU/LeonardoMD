# In-editor search and packaged Help acceptance

Acceptance evidence for [#39](https://github.com/PinedaTec-EU/LeonardoMD/issues/39)
and [#434](https://github.com/PinedaTec-EU/LeonardoMD/issues/434), recorded on
2026-11-12 in the real macOS QA application.

## Tested instance

- Product: LeonardoMD `0.3.1333` stable, build `1333`.
- QA process: PID `72624`, launched with `--new-instance`.
- QA bundle identifier: `eu.pinedatec.LeonardoMD.qa.5a8aa4a28bbf4fc3ad5d2584633f108b`.
- Executable: `LeonardoMD` from the disposable `LeonardoMDQA.app` created by
  `./launch.sh --qa`; bundle verification passed and `otool -L` showed no
  XCTest linkage.
- Profile: isolated `CFFIXED_USER_HOME=/tmp/leonardo-qa-v62/home`.
- App interface locale: English. Both packaged Help locales were opened through
  the actual Help workflow in this process: `Guide-v62-en.mdlz` and
  `Guide-v62-es.mdlz`.
- Extensions while reviewing both guides: Mermaid, Math and Charts enabled;
  Citations and Markdown extras disabled. Math was temporarily disabled to
  inspect its fallback, then restored to enabled.
- The product code was PR head `c38d821f`; the disposable app also included
  guide revision 62 and its resource-path updates. The successful build was
  recorded in PR #40's compilation delta.

## Search interaction

The window contained the English and Spanish guide tabs. Search was entered
from the document toolbar and used the window-wide scope:

- Literal `Leonardo`, case-insensitive, all open documents: **237 matches**.
- The same literal with Match case enabled, all open documents: **200 matches**.
- With Match case enabled and This document selected on the English guide:
  **99 matches** (the case-insensitive English-only count was **117**).
- Regex `\b(Leonardo|documento)\b`, all open documents: **270 matches**.
- A malformed regex (`(`) displayed **Invalid regular expression** and disabled
  previous/next navigation.
- Next/previous moved to the matching guide tab and selected its occurrence.
  Previous from the first result wrapped to `270 of 270` in the English guide.
- The visible search UI showed highlighted occurrences and a distinct current
  match. The accessibility tree reported the search field, toggles, scope,
  result count, active tab and navigation controls.

## Packaged Help and practice form

Both revision-62 guides were opened in this same process using Help. The native
accessibility tree exposed the local cover and illustration images, Mermaid
diagram, chart image, tables, and rendered inline and display equations. With
Math enabled, the one-line equation, underbrace examples, radical/arrow/cancel
example and the tagged box-counting equation `(1)` appeared as equation nodes;
the tagged expression did not expose literal delimiters or a KaTeX error.

With Math temporarily disabled, the one-line and multiline `$$` formulas and
TeX commands appeared as source notation in Preview. The BibTeX code example
remained literal. Math was re-enabled afterwards. The English practice form was
opened from chapter 4 of the packaged guide, edited with fictional values,
saved with ⌘S, closed, and reopened from the guide. The saved name, goal and
checkbox state were present after reopening.

## Capture limitation

Semantic accessibility observations were available for the full acceptance
flow. ScreenCaptureKit later returned
`SCStreamErrorDomain Code=-3811` during screenshot capture, so no screenshot
file is attached to this record. An earlier transient capture showed the yellow
occurrence highlights, but was not persisted as a repository artifact.
