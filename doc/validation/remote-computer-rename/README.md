# Remote computer rename

Native packaged QA on macOS 27.2.1 with Leonardo Classic light and a synthetic revoked localhost connection in an isolated home. Open Preferences → Synchronization → Remote, expand the computer, and choose Rename computer from its menu.

- [Dialog](rename-dialog.png) and [metadata](rename-dialog.metadata.json) show the themed field and focus ring, secondary Cancel and primary Save. Return saved the synthetic name, which appeared in the row and on reopening the dialog.
- [Result after Escape](cancel-result.png) and [metadata](cancel-result.metadata.json) show the previously saved name after editing again and cancelling with Escape.

The verified packaged executable was built at `6963049f08daedfc99e8ac897cf918ee3b9f57a6`, version/build `0.3.2267/2267`. The changes through the reviewed code head `00bda2c0c23f5605ce0a51b4388f61591a00f630` affect only the compilation count. Main's later remote-list refresh changes are outside the rename action and dialog and did not affect the revoked fixture.

No LeonardoMD process was present before launch. QA PID 82530 started on 2026-11-25 at 22:55:14 CET with executable `leonardo-native-qa-5rewekn6/LeonardoMDQA.app/Contents/MacOS/LeonardoMD` and bundle ID `eu.pinedatec.LeonardoMD.qa.0c609b970c3c4923991b01be7a03abb9`. Bundle preflight and dependency inspection passed. The fresh process logged first-window readiness, quit gracefully after validation and was verified absent. No Device Hub session was opened.

On 2026-11-26 the coordinator also verified that the earlier task-owned PID
99097 was absent. It started on 2026-11-24 at 22:11:15 CET from
`leonardo-native-qa-e57rvril/LeonardoMDQA.app/Contents/MacOS/LeonardoMD`.
The original report recorded that the locked-console quit was cancelled.
This later identity-specific check confirms process absence. The exit time
and termination method for that earlier PID were not observed. There was no
Device Hub session to close.
