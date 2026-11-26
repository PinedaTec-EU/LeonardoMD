# PR #610 helper lifecycle validation

Date: 2026-11-26. Product inputs were reconciled from the #610 source head
`7b79a630a81bad8fa6085d4a249a1172886201dd` onto the current release-ledger
main descendant `dab6e5cf4e5ebe6f573f4f73be36e2272bed14db`. The resulting
product tree is the merge commit `1581ea4446f81297ca03bbfd31e9b9d82a6f8983`.
Guide v164 is the current bilingual package; its hashes are recorded in
[`doc/guide/README.md`](../../guide/README.md).

## Deterministic and package checks

- `python3 -m unittest discover -s scripts/tests -p 'test_package_user_guide.py'`: 3 passed.
- `python3 -m unittest discover -s plugins/leonardo-format/tests -p 'test_*.py'`: 52 passed.
- `python3 scripts/compile-and-record.py --pr-number 610 -- swift test --disable-automatic-resolution --filter BundledUserGuideTests`: 4 passed; recorder build delta 16.
- `python3 scripts/compile-and-record.py --pr-number 610 -- swift test --disable-automatic-resolution --filter SyncHelperHostTests`: 7 passed; recorder build delta 17.
- `LEONARDO_SOURCE_PR=610 ./scripts/build-app.sh`: passed; recorder build delta 18, packaged version `0.4.2368 / 2368`.
- `python3 scripts/qa-bundle.py --verify-only output/LeonardoMD.app`: passed. `otool -L` confirmed that the real `LeonardoSyncHelper` has no XCTest dependency.

The disposable QA copy was signed with the local Developer ID identity and
passed `codesign --verify --deep --strict`. Its app identifier is
`eu.pinedatec.LeonardoMD`, helper identifier is
`eu.pinedatec.LeonardoMD.sync-helper`, and both use team `AU2Z3P42U7`. The
helper CDHash was `a1f397ae9770f437bfaf7b37beb071370a5bd386`; the app CDHash
was `404bff0d299f34c7a8d76a9d69d28f92765bade6`.

## Controlled direct-helper run

No GUI, simulator, launchd bootstrap, installed hook, host registration or
credential change was used. Before launch, no exact `LeonardoSyncHelper`
process existed; the installed app-support root was owned by the user with
mode `0700`, and the real user `~/Library/Application Support/LeonardoMD/Preview`
leaf was absent.

The signed helper was launched directly with an isolated `HOME` and
`CFFIXED_USER_HOME`. The isolated preferences enabled Sync and the optional
preview with `host=0.0.0.0`, an empty project list and port `40882`. The invalid
host was rejected before TLS identity materialization: isolated
`MobileSync/TLS` and `MobileSync/devices.json` remained absent. The separately
reconciled bundled Python worker started with the supported Homebrew Python
3.14 interpreter and published a loopback endpoint on port `58768`. The
task-owned `Preview` directory was `0700`, and its endpoint was user-owned
`0600` with a 43-character token.

The exact task processes were helper PID `33810` and Python worker PID `33820`.
Both were gone after teardown. The task-owned endpoint and `Preview` leaf were
removed after process exit, and the real user's Preview leaf remained absent.
The direct process run therefore establishes the isolated helper/worker start,
loopback publication and exact teardown boundary. Because the run deliberately
used a direct process rather than launchd, it does not claim installed-helper,
browser-link, Stop-hook trust or distribution-app acceptance; those remain
Beta validation scope.
