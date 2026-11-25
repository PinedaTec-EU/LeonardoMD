# Table pagination acceptance

The [native Preview](pagination.png) shows the first fragment ending at Record 05 and the next fragment starting with a repeated header and Record 06. The synthetic MDLF has a 420 × 360 point custom page, 28 body rows and an authored page break after the table. See [capture metadata](pagination.metadata.json). The checked-in PNG captures and their metadata are the earlier v145 visual record; the current v146 packaged Help smoke is recorded below.

## Current candidate revalidation

On 2026-11-26 CET, the reconciled candidate was validated from source SHA
`940948e76c7e0eb06a553f657cb5e857d0f6da6e` after rebasing onto
`ca526517fe5b48bc00b2c9edbc5f57943e2b713e` (`origin/main`). The five focused
`TablePaginationTests` passed, including the meaningful heading boundary and
unsupported `colspan`/`rowspan` PDF rejection regressions. The packaged QA
build was produced with `./launch.sh --qa`; its executable was `LeonardoMD`
and `otool -L` showed no XCTest linkage.

The fresh QA process was PID 888, started at 00:32:53 CET, from
`LeonardoMDQA.app` with bundle identifier
`eu.pinedatec.LeonardoMD.qa.ccf07e4a52344c348d7705c1df09cb36`. It reached its
first window after dismissing the existing restored-document metadata warning
(`unknownMetadataKey("document.signing.method")`) and release-notes window.
The English Help menu opened the v146 user-owned copy; its chapter 7 and
chapter 10 passages rendered and its SHA-256 matched the bundled
`3b863449ff6fe5cbc1051b7fe57bb3fb823b0ae818c234aa61c97030274a1489` copy.
The Spanish v146 resource was opened directly from the QA worktree because the
English QA instance does not switch Help locale; its chapter 7 and chapter 10
passages rendered and its bundled SHA-256 is
`a063da2b8f0a6a30afecaeea56cdf8012bf2d0ef135a9110a9211e642577c480`.
The owned process quit via the app command and PID 888 was verified absent;
the pre-existing XCTest process in worktree #514 was left untouched.

The current Help text includes the #605 chapter 7 remote-menu sentence and the
table continuation guidance in both locales. Existing guide copies and
practice answers were not overwritten.

The prior packaged-equivalence record is pinned to the full source SHA
`07f6e12f080f6c68670c271464e6c901b58ffcc6` and reports `0.3.2298 / 2298`.
Its five affected renderer resources were:

* `leonardo-objects.js` — `93e2275c20f538494be1d1a47fe988a3e4373cb87bcb4edf1e3043b485789c58`
* `table-pagination.js` — `780eb359457cdc70f10c4f53023ec25710a88c05f909304289a487dd8a7427e7`
* `renderer-runtime.js` — `d19ae0be064fd7c9528979ff92bf45bbf56199b963a02d96d89e6a217f865343`
* `table-resizing.css` — `ade20ac38af6e367ef32466f66af3bfd8d56f79046eb7d32da21762bf0a71c9e`
* `table-resizing.js` — `54651f038fa6c909a1cfa58ef1f5a1a6f4c01ad2fcdf87ffdfd7baa0bfdd0c0a`

The same record used Guide v145 EN `06e9882035b7eb210e398765da5b331423257738cc3b302fea1c9f5e2e2d4856`
and ES `af520d3730fe3bba8fcc983542cba16bd724c26ef7ff11832fd6dd170d73c070`.
After rebasing onto current `origin/main` SHA
`ca526517fe5b48bc00b2c9edbc5f57943e2b713e`, the candidate sources regenerate
Guide v146 from the exact bilingual bodies (EN
`be50cd9ecdb1b2ed8b981772097ed97fca9e5695450f769b689e951b94420a4c`, ES
`4f4eacbbd00201abd493fe38ef123acaeb06e0366c8ac446b69d98a0d75c74f7`).
The v146 package hashes are recorded in `doc/guide/README.md`; they include
#605's chapter 7 sentence and the table-pagination guidance. The regenerated
packages have not received a new packaged GUI acceptance in this reconciliation
pass.

The five `TablePaginationTests` currently cover row continuity, header settings,
matching widths, authored page breaks, heading-boundary geometry, unsupported
colspan/rowspan PDF rejection, PDFKit text and over-height row rejection.

Packaged QA PIDs 92903 (23:00:10), 16898 (23:23:50) and 19646 (23:26:25) ran on 2026-11-25 CET from `leonardo-native-qa-y3b_93qo/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`, bundle `eu.pinedatec.LeonardoMD.qa.1cabad2bee07437cac0b1c27ddbc8e70`. Each logged a fresh first window, quit gracefully and was verified absent. No Device Hub or simulator session was opened.
