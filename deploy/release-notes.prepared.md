# Prepared release notes

These versions are materialized. Publication or deployment is not claimed.

## 0.1.671

- #282 Added: validate evidence compilation counts ([#283](https://github.com/PinedaTec-EU/LeonardoMD/pull/283))

<p>PR evidence compilation counts are generated from the ledger and automatically checked for stale or inconsistent declarations.</p>

Source: `9fc34be8a2516ce171baa259f4d341c20315ed01`. Delta: `{"build": 1}`.

## 0.1.670

- #277 Added: extend document rendering and scoped preferences ([#278](https://github.com/PinedaTec-EU/LeonardoMD/pull/278))

<p>Documents gain optional offline charts, citations and richer Markdown structures, with controls for global and project preferences.</p>

Source: `b6efccf1c322003772f287d3ebbbb63ed80278c5`. Delta: `{"build": 9}`.

## 0.1.661

- #275 Fixed: monitor external MDLZ source changes ([#276](https://github.com/PinedaTec-EU/LeonardoMD/pull/276))

<p>Open MDLZ documents refresh after external changes; unsaved edits are protected with a choice to reload the disk version or save a copy.</p>

Source: `484f6ce0d011b9a67aeebfe5148eb25c613836d6`. Delta: `{"build": 9}`.

## 0.1.652

- #212 Fixed: preserve PDF export across preview mode transitions ([#271](https://github.com/PinedaTec-EU/LeonardoMD/pull/271))

<p>PDF export keeps working after switching between Preview and Split, including portable documents with local images and Mermaid diagrams.</p>

Source: `bab08eded742d50d3f486f1fdcac08f9f47fd190`. Delta: `{"build": 6}`.

## 0.1.646

- #202 Fixed: coordinate normal instance closure before updates ([#270](https://github.com/PinedaTec-EU/LeonardoMD/pull/270))

<p>Updates close additional instances before downloading, preserve document and Git checks on Quit, and stop when an instance stays open. Automatic checks remain available; downloads require approval.</p>

Source: `1d6dc51ca4430bb4826a94eedea0ae2579ccfac0`. Delta: `{"build": 16}`.

## 0.1.630

- #268 Fixed: confirm permanent deletion when Trash is unavailable ([#269](https://github.com/PinedaTec-EU/LeonardoMD/pull/269))

<p>Files and folders on locations without Trash can be permanently deleted after an explicit warning, while ordinary Trash errors continue to preserve the original item.</p>

Source: `ed42b9d11b215b42d1f743201a99b3bbe1cc1c07`. Delta: `{"build": 2}`.

## 0.1.628

- #266 Fixed: prevent startup crash when preferences suite is unavailable ([#267](https://github.com/PinedaTec-EU/LeonardoMD/pull/267))

<p>Fix a crash before the first window when macOS cannot open the instance preferences suite.</p>

Source: `cd7ae22a3fe461f65d825cc09af772d5e3bc8475`. Delta: `{"build": 3}`.

## 0.1.625

- #263 Added: configurable explicit application instances ([#264](https://github.com/PinedaTec-EU/LeonardoMD/pull/264))

<p>Opt into independent editor instances while Finder opens stay with the principal; document reservations and coordinated preference writes protect shared data.</p>

Source: `db4e98628100f17ea4e71d2b54d4b29d2af6d8de`. Delta: `{"build": 11}`.

## 0.1.614

- #261 Added: highlight file and folder rows on hover ([#262](https://github.com/PinedaTec-EU/LeonardoMD/pull/262))

<p>File and folder rows now highlight with the active accent color on hover in the project navigator, search results, and welcome favorites and recents.</p>

Source: `785cf1a5917b8a78851a4af2802a24809020d766`. Delta: `{"build": 2}`.

## 0.1.612

- #259 Fixed: restore document window geometry ([#260](https://github.com/PinedaTec-EU/LeonardoMD/pull/260))

<p>Reopened document windows keep their size, position and monitor, and remain reachable when a display is disconnected.</p>

Source: `3c46fc7efd5be799068188d8dc6565038630847c`. Delta: `{"build": 6}`.

## 0.1.606

- #257 Fixed: recognize stable promotion without changing subscription ([#258](https://github.com/PinedaTec-EU/LeonardoMD/pull/258))

<p>Installed betas recognize a verified promotion to stable in About, the footer and Preferences while preserving the selected update subscription, including offline recognition after verification.</p>

Source: `f4af1cbd8932a49c204e202f389fd7e5196e35d4`. Delta: `{"build": 6}`.

## 0.1.600

- #254 Added: reopen release notes from About ([#255](https://github.com/PinedaTec-EU/LeonardoMD/pull/255))

<p>You can reopen hidden release notes from About, as well as from the macOS application menu.</p>

Source: `959dfb3a8ccf52de2f9118979094f516b178f9a2`. Delta: `{"build": 5}`.

## 0.1.595

- #243 Fixed: bound document image loading and raster resolution ([#245](https://github.com/PinedaTec-EU/LeonardoMD/pull/245))

<p>Local document images use bounded loading and preview resolution, while PDF export requests higher resolution without modifying original assets.</p>

Source: `c7b6c39210bf094126bd19de0e4e62cd736b2d4d`. Delta: `{"build": 21}`.

## 0.1.574

- #252 Fixed: theme release notes with the owning document ([#253](https://github.com/PinedaTec-EU/LeonardoMD/pull/253))

<p>Release notes follow the active document theme and use the shared application button style.</p>

Source: `1e083eebf3fa4d22db61818410f67c56b63486d1`. Delta: `{"build": 3}`.

## 0.1.571

- #247 Fixed: attach auxiliary windows and document dialogs as modal sheets ([#248](https://github.com/PinedaTec-EU/LeonardoMD/pull/248))

<p>About, Release notes, confirmations and file selection attach as modal sheets; file actions reject changes to the active project or workspace.</p>

Source: `5ba81b9826dccb11ef3ac6ba5ec25c4e382f58cb`. Delta: `{"build": 13}`.

## 0.1.558

- #249 Refactored: retire proprietary mobile Git ([#250](https://github.com/PinedaTec-EU/LeonardoMD/pull/250))

<p>Little Leonardo becomes read-only, preserves older work against cache overwrites and exports it for recovery; proprietary Git is retired while desktop synchronization and system Git remain available.</p>

Source: `0b366528be0f199facd52eff45a5cd4d5af0d9d7`. Delta: `{"build": 11}`.

## 0.1.547

- #241 Fixed: move user deletions to Trash ([#242](https://github.com/PinedaTec-EU/LeonardoMD/pull/242))

<p>Deleted files, folders and projects now move to Trash so they can be recovered.</p>

Source: `dd7a3de66b62e6621b7e2c07030a1334948e5cf5`. Delta: `{"build": 12}`.

## 0.1.535

- #216 Added: export Leonardo reading copies as Markdown ([#217](https://github.com/PinedaTec-EU/LeonardoMD/pull/217))

<p>Export Leonardo documents and form answers as Markdown with a loss warning and portable image handling.</p>

Source: `c0bb701166c155c77b9a73aa52659107436a51b3`. Delta: `{"build": 14}`.

## 0.1.521

- #232 Fixed: enlarge form calendars and follow document themes ([#233](https://github.com/PinedaTec-EU/LeonardoMD/pull/233))

<p>Form date fields offer a larger calendar in the active theme, with localized labels, keyboard navigation and a safe fallback for malformed locales, while preserving editable drafts.</p>

Source: `0ba65a49d3777c3aca2ca72df4b461d6b72c6903`. Delta: `{"build": 12}`.

## 0.1.509

- #236 Added: promote an exact beta without changing its version ([#237](https://github.com/PinedaTec-EU/LeonardoMD/pull/237))

<p>Promote a chosen validated beta to stable while preserving its version and exact signed artifact, even when newer betas exist.</p>

Source: `5bfd788e6efba9c28f344fbf9011898eaff7e659`. Delta: `{"build": 2}`.

## 0.1.507

- #234 Fixed: preserve form presentation in Preview and Split ([#235](https://github.com/PinedaTec-EU/LeonardoMD/pull/235))

<p>Preview and Split preserve the field presentation shown in Fill form.</p>

Source: `4fa8f5b8244edba348550858c14b428d4cbc3c36`. Delta: `{"build": 5}`.

## 0.1.502

- #230 Added: document undo and redo history ([#231](https://github.com/PinedaTec-EU/LeonardoMD/pull/231))

<p>Undo and redo document edits from the toolbar or keyboard, with separate history for each document and support for source, preview and form editing.</p>

Source: `5572d4b2cb0888e028a9e2b4a5c2b0eec5d86fa5`. Delta: `{"build": 4}`.

## 0.1.498

- #228 Added: file list colors filtering and sorting ([#229](https://github.com/PinedaTec-EU/LeonardoMD/pull/229))

<p>Distinguish Leonardo files in wine, configure file colors globally or per project, and filter and sort the project file list.</p>

Source: `a572fd54377cc9cb36c2e5837b8053d229684ecb`. Delta: `{"build": 4}`.

## 0.1.494

- #220 Fixed: improve light-theme document indicator contrast ([#221](https://github.com/PinedaTec-EU/LeonardoMD/pull/221))

<p>Improve document format and storage indicator contrast in light themes using the palette heading color.</p>

Source: `4ece950ef7c3c181340450074ab27ef18c2437c5`. Delta: `{"build": 3}`.

## 0.1.491

- #208 Added: resize preview tables with persisted MDLF geometry ([#213](https://github.com/PinedaTec-EU/LeonardoMD/pull/213))

<p>Resize columns, rows and whole tables in Preview with the mouse or keyboard. Markdown documents migrate safely to MDLF to preserve table dimensions.</p>

Source: `ca0e3686c45ad580a5a399562501142aec7cbddf`. Delta: `{"build": 9}`.

## 0.1.482

- #209 Added: per-PR summaries and native startup release notes ([#210](https://github.com/PinedaTec-EU/LeonardoMD/pull/210))

<p>LeonardoMD shows the changes included in each new version at startup. You can hide the notice for that version or reopen it from the application menu.</p>

Source: `45fcdebc654eb7f944dbc734081824d37350b699`. Delta: `{"build": 6}`.

## 0.1.476

- #206 Added: inline form controls and contextual field help ([#207](https://github.com/PinedaTec-EU/LeonardoMD/pull/207))

Source: `32ebcb6fe30cbdec3d13e5a6ea1a8557a63936e9`. Delta: `{"build": 10}`.

## 0.1.466

- #204 Fixed: omit empty optional Leonardo metadata ([#205](https://github.com/PinedaTec-EU/LeonardoMD/pull/205))

Source: `b40aaeb95389dbf952d58f2b80908c5e737d46cc`. Delta: `{"build": 2}`.

## 0.1.464

- #198 Added: checkbox and switch form appearances ([#199](https://github.com/PinedaTec-EU/LeonardoMD/pull/199))

Source: `e098a85483aed9da0e6c1ec3e85af12deda9c69a`. Delta: `{"build": 3}`.

## 0.1.461

- #191 Fixed: preserve Markdown metadata during MDLF migration ([#192](https://github.com/PinedaTec-EU/LeonardoMD/pull/192))

Source: `78b37c0b83b3299ea7c29b54b2434b1c657fba38`. Delta: `{"build": 6}`.

## 0.1.455

- #196 Fixed: keep MDLF JSON metadata out of invoice preview ([#197](https://github.com/PinedaTec-EU/LeonardoMD/pull/197))

Source: `ab9bc550ca56295e7e2bceb6dfc4a2c43597216d`. Delta: `{"build": 10}`.

## 0.1.445

- #189 Fixed: Open MDLF and MDLZ documents in preview by default ([#190](https://github.com/PinedaTec-EU/LeonardoMD/pull/190))

Source: `4f330d747986bce95c1398f4b9322f3be20024c2`. Delta: `{"build": 4}`.

## 0.1.441

- #183 Fixed: Refresh format preferences and shorten package choices ([#184](https://github.com/PinedaTec-EU/LeonardoMD/pull/184))

Source: `0f11f8b1a6b79b1c5b3d43f35bf01379c0500575`. Delta: `{"build": 4}`.

## 0.1.437

- #185 Added: preferences gear beside new tab ([#186](https://github.com/PinedaTec-EU/LeonardoMD/pull/186))

Source: `c1b2f894fcb0fbec87da682f2a9ca53ad5dbe53a`. Delta: `{"build": 2}`.

## 0.1.435

- #167 Added: open Leonardo documents, forms and agent plugins ([#168](https://github.com/PinedaTec-EU/LeonardoMD/pull/168))

Source: `11f699c64f9bba03789871d08db5782e005c038b`. Delta: `{"build": 28}`.

## 0.1.407

- #173 Fixed: keep preference scope inside its tab ([#174](https://github.com/PinedaTec-EU/LeonardoMD/pull/174))

Source: `37ac8fe0ed61318611a1c7bf4ccfaea7245e22a7`. Delta: `{"build": 2}`.

## 0.1.405

- #15 Updated: promote validated beta 0.1.404 to stable ([#162](https://github.com/PinedaTec-EU/LeonardoMD/pull/162))

Source: `2dfa983b9e4e92578e595b197ddfd863a7a407a2`. Delta: `{"build": 1}`.

## 0.1.404

- #160 Fixed: deduplicate recent project and workspace paths ([#161](https://github.com/PinedaTec-EU/LeonardoMD/pull/161))

Source: `42a57f14c8f1429adde18ac67c5373e8dc0c5f95`. Delta: `{"build": 2}`.

## 0.1.402

- #158 Fixed: restore large Leonardo background beneath scrolling Home ([#159](https://github.com/PinedaTec-EU/LeonardoMD/pull/159))

Source: `08b15075af45b22f81d5602d01c41be3e46d3d03`. Delta: `{"build": 3}`.

## 0.1.399

- #156 Updated: compact Home recents and adapt Leonardo background ([#157](https://github.com/PinedaTec-EU/LeonardoMD/pull/157))

Source: `a62e099bc740851ba615049b358b8a2805a8e31e`. Delta: `{"build": 3}`.

## 0.1.396

- #15 Added: promote accepted beta 395 to stable ([#155](https://github.com/PinedaTec-EU/LeonardoMD/pull/155))

Source: `d522b9aadc1b992fd659d52c01dc7504823631b7`. Delta: `{"build": 1}`.

## 0.1.395

- #144 Added: protected preview editing and manual saving ([#145](https://github.com/PinedaTec-EU/LeonardoMD/pull/145))

Source: `350cc9b5e09d111e689284cd30eb44a49f1742c1`. Delta: `{"build": 20}`.

## 0.1.375

- #146 Added: heading-colored border to document metadata ([#147](https://github.com/PinedaTec-EU/LeonardoMD/pull/147))

Source: `4747278c9984fef3847feed6a1f09d1576404b47`. Delta: `{"build": 2}`.

## 0.1.373

- #142 Fixed: show installed channel beside application version ([#143](https://github.com/PinedaTec-EU/LeonardoMD/pull/143))

Source: `90a336482a322642140b3f040c8743b03933a550`. Delta: `{"build": 3}`.

## 0.1.370

- #15 Added: promote validated beta 369 to stable ([#141](https://github.com/PinedaTec-EU/LeonardoMD/pull/141))

Source: `48b477871f74a285b9ff5be96bb6925a581db11e`. Delta: `{"build": 1}`.

## 0.1.369

- #137 Added: persist favorites and show welcome item lists ([#138](https://github.com/PinedaTec-EU/LeonardoMD/pull/138))

Source: `754cfe63dd715e06ba70885a68170f8587e1f8f6`. Delta: `{"build": 8}`.

## 0.1.361

- #136 Fixed: isolate sidebar context menu button styling ([#139](https://github.com/PinedaTec-EU/LeonardoMD/pull/139))

Source: `ae5af291fa0fadd63c573c8f76fd2f42969e632f`. Delta: `{"build": 3}`.

## 0.1.358

- #133 Added: offer default Markdown application choice ([#134](https://github.com/PinedaTec-EU/LeonardoMD/pull/134))

Source: `dba651f58275b1714678eb0a06aa0af9944c43d7`. Delta: `{"build": 5}`.

## 0.1.353

- #130 Fixed: support Markdown table width comments ([#131](https://github.com/PinedaTec-EU/LeonardoMD/pull/131))

Source: `cc3be97d99542efc216ca694ea7144629593c274`. Delta: `{"build": 3}`.

## 0.1.350

- #128 Updated: Move language into General preferences ([#129](https://github.com/PinedaTec-EU/LeonardoMD/pull/129))

Source: `6611285bbe8d240e7a29c079a9e0b17a6900bc8a`. Delta: `{"build": 1}`.

## 0.1.349

- #15 Added: allocate builds for validated stable promotions ([#127](https://github.com/PinedaTec-EU/LeonardoMD/pull/127))

Source: `b660146e1220cf383a04bcfa33d71ab01e77ec33`. Delta: `{"build": 1}`.

## 0.1.348

- #123 Added: user-selected beta channel and update preferences ([#124](https://github.com/PinedaTec-EU/LeonardoMD/pull/124))

Source: `04eaaeb524882ed1859412f6c55ba6d3cd25c641`. Delta: `{"build": 11}`.

## 0.1.337

- #92 Added: implement Little Leonardo and desktop peer synchronization ([#93](https://github.com/PinedaTec-EU/LeonardoMD/pull/93))

Source: `a2ff7c96e36f55d8eca39f96f55ae221ebb82497`. Delta: `{"build": 193}`.

## 0.1.144

- #88 Removed: redundant Preferences button from document outline ([#89](https://github.com/PinedaTec-EU/LeonardoMD/pull/89))

Source: `d4b4dc511d22e6cd431b4e8eb58e235fab458f0d`. Delta: `{"build": 4}`.

## 0.1.140

- #86 Added: resizable project sidebar ([#87](https://github.com/PinedaTec-EU/LeonardoMD/pull/87))

Source: `7b7348a9dce81cf86e340f131b60e8da3c80a733`. Delta: `{"build": 5}`.

## 0.1.135

- #78 Added: expose recent documents projects and workspaces in File ([#79](https://github.com/PinedaTec-EU/LeonardoMD/pull/79))

Source: `366a90b590f2d0e4a8e5db42247a71bca5fb1702`. Delta: `{"build": 11}`.

## 0.1.124

- #75 Added: subtle Leonardo welcome watermark ([#76](https://github.com/PinedaTec-EU/LeonardoMD/pull/76))

Source: `99903268d818758d319cdee450f6bfc411b5477c`. Delta: `{"build": 11}`.

## 0.1.113

- #80 Fixed: build native QA copies from the real app bundle ([#82](https://github.com/PinedaTec-EU/LeonardoMD/pull/82))

Source: `1c0113257daab469a7a09f239ed2966a7b0e8f3f`. Delta: `{"build": 2}`.

## 0.1.111

- #69 Added: request central ledger processing after source merges ([#71](https://github.com/PinedaTec-EU/LeonardoMD/pull/71))

Source: `a1701431cd9ade68da919a26b834f7f5aa9644ba`. Delta: `{"build": 1}`.

## 0.1.110

- #53 Fixed: keep numeric versions across update channels ([#54](https://github.com/PinedaTec-EU/LeonardoMD/pull/54))

Source: `21e0ce2a6cd2069af68123382f648e81c5468a1a`. Delta: `{"build": 5}`.

## 0.1.105

- #47 Changed: remove redundant sidebar configuration button ([#48](https://github.com/PinedaTec-EU/LeonardoMD/pull/48))

Source: `1d4789848ad283bd93fbd01eeb0e05c0c0ea9555`. Delta: `{"build": 2}`.

## 0.1.103

- #57 Added: English and Spanish interface languages ([#58](https://github.com/PinedaTec-EU/LeonardoMD/pull/58))

Source: `19462dd860a2892cc7a8f022270b4ca398e83d93`. Delta: `{"build": 17}`.

## 0.1.86

- #38 Updated: refresh engine for accepted notes proposals ([#66](https://github.com/PinedaTec-EU/LeonardoMD/pull/66))

Source: `63d4741fa78b7b7c84609e504cc84464c647f1b6`. Delta: `{"build": 1}`.

## 0.1.85

- #38 Updated: activate checkpoint-aware ledger and document signed release ([#64](https://github.com/PinedaTec-EU/LeonardoMD/pull/64))

Source: `e594acfa496ca560065d0c9113a40d7d1c9117ff`. Delta: `{"build": 1}`.

## 0.1.84

- #51 Fixed: enable pointer reordering of document tabs ([#52](https://github.com/PinedaTec-EU/LeonardoMD/pull/52))

Source: `fe9bccfbe365952dfd0a359ea38c22f612fb8391`. Delta: `{"build": 20}`.

## 0.1.64

- #38 Updated: refresh ledger engine and isolate release fixtures ([#59](https://github.com/PinedaTec-EU/LeonardoMD/pull/59))

Source: `dbddd4b3f6e39713e1590fb5947b51e495fcab9e`. Delta: `{"build": 3}`.

## 0.1.61

- #38 Updated: request central ledger policy by dispatch ([#50](https://github.com/PinedaTec-EU/LeonardoMD/pull/50))

Source: `0f13bbd6692f6bbc10acb6c0ff94136df7ace69e`. Delta: `{"build": 1}`.

## 0.1.60

- #38 Added: adopt shared release ledger from 0.1.56 ([#42](https://github.com/PinedaTec-EU/LeonardoMD/pull/42))

Source: `49665943fe9d154988987d4204fbc1e1802fc53d`. Delta: `{"build": 4}`.
