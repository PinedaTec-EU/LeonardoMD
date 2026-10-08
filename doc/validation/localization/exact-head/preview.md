# Native preview

Source head: `9e870dbb91b6940b114337454eb5c99dd8ced364`.

Build the committed tests with `swift test`. `LocalizationVisualTests` can retain real windows when both `LEONARDO_LOCALIZATION_EVIDENCE=/tmp/leonardo-localization-preview` and `LEONARDO_LOCALIZATION_LIVE_QA=1` are supplied. Run its `testCapturePreferencesAndWorkspaceInBothLanguages` with Xcode XCTest.

For CUA discovery, copy `/Applications/Xcode.app/Contents/Developer/usr/bin/xctest` into `output/LocalizationQA.app/Contents/MacOS/LocalizationQA`, use an APPL Info.plist with executable LocalizationQA and bundle ID eu.pinedatec.LocalizationQA58, and ad-hoc sign the QA app. Launch via `open -n` with the two environment values above plus DYLD_FRAMEWORK_PATH=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks and DYLD_LIBRARY_PATH=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib. Pass arguments `-XCTest LeonardoAppTests.LocalizationVisualTests/testCapturePreferencesAndWorkspaceInBothLanguages` and the absolute `.build/out/Products/Debug/LeonardoAppTests.xctest` path.

Select LocalizationQA in CUA. Capture English Preferences, select About from Window without closing Preferences, then return to Preferences and select Español. Close the sheet to capture the tab, then select the existing Acerca de window from Window. Accessibility files contain the grip Help and Description. The window is retained; no second About presentation occurs after the language change. Normal macOS Window-menu system items and the QA shell title are outside application localization. The harness uses temporary documents/preferences and does not claim the production app's single-instance service.

All captures were made by the implementation agent after the source-head commit. Tabs include titlebar at 1260×882 points; Preferences sheet is 580×620; About including titlebar is 720×596. Pixels are 2× these dimensions. The synthetic document render area is not used as evidence for Markdown rendering; these captures prove localized native controls, grip and About content/title only.
