# Historical candidate after main refresh (superseded)

Current acceptance is recorded in [../scroll-feedback/README.md](../scroll-feedback/README.md). This candidate predates the delayed-scroll correction and is retained as historical evidence.

Tracking [PR #377](https://github.com/PinedaTec-EU/LeonardoMD/pull/377), [#274](https://github.com/PinedaTec-EU/LeonardoMD/issues/274), [#364](https://github.com/PinedaTec-EU/LeonardoMD/issues/364).

Source `ce121b2c8ecdea17f2f7bbd9fc802092bcb3f5ff`, Guide v20, unmaterialized baseline 0.3.1022. Incorporates accepted Classic illustrations and AgentImport v3 from main. Revision 20 was reserved across concurrent threads; existing copies 18/19 and practices were preserved.

Original current images: [English component](component-en.png), [Spanish component](component-es.png), [English packaged app](packaged-en.jpg), [Spanish packaged app](packaged-es.jpg). Every image has adjacent capture context and hash-bound metadata. Native CUA browser/CSS viewport are unavailable and null; both native images are 2520×1700 pixels. Component context records measured viewport/User-Agent. No original was edited.

Fresh QA PID53575, real executable and packaged dependencies, no XCTest linkage; first release-notes window and subsequent document window observed. See [native record](native-qa.json) for archive/executable hashes. Both Help-opened personal archives match source and bundle byte-for-byte. Braces, radical, arrow, cancel and equation tag are complete; outline selection/repeated selection after scrolling and Split retain the target. Math disabled preserves literal source in both locales; recommendations dismissed without remembered suppression. Both practices saved/closed/reopened fictional names, then original blank names restored/saved. Original English, Math=true and Classic/Parchment restored; process quit normally. Other threads ceded GUI before QA.

Full native suite: 699 XCTest cases,35 skipped,0 failures;70 Swift Testing cases pass. Script suite111 tests,7 skipped,pass. Guide capture test passes.19 successful compiler invocations recorded. Logs retained locally under `/tmp/leonardo-377-v20-{full,scripts,captures,launch}.log`; CI provides durable independent reruns.

Reproduce: use a clean worktree at reviewed SHA, run `python3 scripts/compile-and-record.py --pr-number 377 -- swift test`; run script suite; obtain guide captures with `LEONARDO_VISUAL_EVIDENCE` and `EVIDENCE_SHA` using BundledUserGuideTests.testNativeReadingGuideImagesAndActionRenderInBothLanguages. For packaged acceptance, coordinate exclusive GUI, run `LEONARDO_SOURCE_PR=377 ./launch.sh --qa`, verify executable/dependencies/new PID, open both Help locales, compare bundle/source/personal archives before counting results, select regression headings, test repeated selection/Split, Math on/off and practice persistence; restore preferences/data and quit.

Run `python3 doc/validation/math-outline/verify-source-mapping.py <reviewed-SHA>` to prove all product/build/test/guide/workflow inputs match the capture source; only evidence and compilation entry may differ. Parent-directory captures are historical v18 evidence, not current acceptance. Separate findings #378 (general QA copy isolation) and #379 (long tagged formulas in narrow Split; widen/use Preview) remain open.
