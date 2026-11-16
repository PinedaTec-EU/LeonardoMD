# PR #435 bilingual iOS evidence

This record is tied to product source `412740cc1053235f1fdf8803d142022003347594` (tree `d8f56b24a682ea61ca1613e515cf20627654bbaa`). The English and Spanish screenshots are raw XCTest attachments from the two passing, exact-source simulator runs. Each alert reference is visible again in the matching local error log.

## Validation

- `swift test`: passed; compilation build 86.
- Spanish `OnDemandSyncUITests/testCatalogueContextRetentionAndSeparateCache()`: 1 passed, 0 failed, 0 skipped; build 87.
- English `OnDemandSyncUITests/testEnglishSharedDownloadFailureLocalizesVoiceOverCopy()`: 1 passed, 0 failed, 0 skipped; build 88.
- Synthetic host fixture audits are included as JSON. They record two Spanish catalogues with one explicit file fetch, and one English catalogue.

## Diagnosed retries

The first simulator install failure happened before XCTest: InstallCoordination rejected the 74 MB `.xctestproducts` bundle on the external volume with `MIInstallerErrorDomain Code 232`, because its volume UUID did not match the system transfer location. Copying the same bundle to `/private/tmp` on the system volume allowed the test to run. The environment issue is registered separately as [#456](https://github.com/PinedaTec-EU/LeonardoMD/issues/456).

A later retry reused simulator app state and showed a prior loopback host alongside the new host. We erased only this task-owned simulator and repeated both locale runs from clean app containers; both passed. This retry does not indicate a failing product assertion on a clean run.

## Teardown

The task-owned simulator `5B689430-FDBD-44C0-A732-BE3C063F9403` ended in Shutdown after the English pass. The fixture exited and its port closed; no task-owned LittleLeonardo or XCTest process remained. The separate pre-existing simulator was left running.

All error responses and document data were synthetic loopback fixtures. No physical camera or device-transfer acceptance is claimed.
