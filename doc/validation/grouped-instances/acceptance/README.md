# Reconciled candidate acceptance checkpoint

Product source: `29b8493f97a4747068b02ae8c9111a61164e9a66`, based on current main
`2542a940c2b7c964ab4ed29cb72fefefb53f9c64`. Version 0.3.1587/build 1587, Guide v71.
Later checkpoint commits contain evidence and compilation allocation only.

Local validation: 902 XCTest cases (41 optional skips), 72 Swift Testing cases,
zero failures; three deterministic guide-packaging tests passed.

## Completed live acceptance

Process B (PID 95948, bundle `eu.pinedatec.LeonardoMD.qa.a794635da723448fb60b33db6cd0860f`)
opened both guides through the native application's Help menu while accessory.
Mermaid, local images, charts, tables, inline/display math, underscores,
underbraces and the tagged equation were inspected. Math-disabled fallback kept
literal TeX in each language; code examples stayed literal. Math was restored.
Both practice forms were opened, filled, saved, closed and reopened with the
saved synthetic values. Transcripts and captures record those actual states.
Keyboard checks explicitly activated the target instance before sending keys.
`identity.json` binds both guide copies to the bundled hashes and practice values.

CFFIXED_USER_HOME isolates Foundation home/Application Support and document data;
per-Mac instance preferences still use the normal account's shared domain. The
same custom home was initially used by presenter A (PID 94348) and B. A's Help
attempt correctly encountered B's process-lifetime path lease even after tab
close. A was closed normally and B took over regular policy. That shared-profile
attempt is superseded by the per-process repeat, not counted as presenter Help
acceptance. Product source and ownership behavior were not changed for QA.

## Pending — locked Mac

Replacement A2 (PID 7354, bundle `eu.pinedatec.LeonardoMD.qa.3a0bffd58ffc421f82471e787b12a646`)
uses a distinct temporary home and logged accessory policy. CUA then reported
that the Mac is locked and automatic unlock failed. Manual owner unlock was
requested. A2's bilingual matrix, unsaved-quit cancellation, and safe teardown
of B/A2 plus restoration of shared grouping remain pending. Existing sessions
were preserved; no Device Hub session was created. This is not final acceptance,
a judge verdict, self-approval or permission to merge.

Original image bytes are JPEG. Sidecars use the common capture helper; native
pixel dimensions occupy its compatibility viewport fields because CSS viewport
and browser version are not applicable/exposed. Earlier captures outside this
folder are historical and do not establish acceptance of the reconciled source.
