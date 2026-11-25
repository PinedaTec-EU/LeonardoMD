# Table pagination acceptance

The [native Preview](pagination.png) shows the first fragment ending at Record 05 and the next fragment starting with a repeated header and Record 06. The synthetic MDLF has a 420 × 360 point custom page, 28 body rows and an authored page break after the table. See [capture metadata](pagination.metadata.json).

The native Help menu opened the packaged v145 editions. The updated passages rendered in [English](chapter-en.png) and [Spanish](chapter-es.png). Both Help-created copies in the isolated home match the bundled resources byte for byte. [English metadata](chapter-en.metadata.json) · [Spanish metadata](chapter-es.metadata.json).

The three `TablePaginationTests` verify row continuity, header settings, matching widths, authored page breaks, PDFKit text and over-height row rejection. Captures came from the real packaged application without XCTest linkage. The build used reconciled source `07f6e12f080f6c68670c271464e6c901b58ffcc6` and reports `0.3.2298 / 2298`. The five affected renderer resources and both guides match the reviewed source byte for byte.

Packaged QA PIDs 92903 (23:00:10), 16898 (23:23:50) and 19646 (23:26:25) ran on 2026-11-25 CET from `leonardo-native-qa-y3b_93qo/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`, bundle `eu.pinedatec.LeonardoMD.qa.1cabad2bee07437cac0b1c27ddbc8e70`. Each logged a fresh first window, quit gracefully and was verified absent. No Device Hub or simulator session was opened.
