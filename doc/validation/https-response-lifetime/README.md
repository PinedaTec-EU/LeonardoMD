# HTTPS response lifetime investigation

Canonical bug: [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380).

The owner supplied `physical-partial-body-20261107.png`, captured on a physical iPhone at11:47 on7 November2026. It shows `[LL1 op=snapshot domain=NSURLErrorDomain code=-1005 http=200 bytes=409481/492904]`. Original PNG1290×2796, SHA256 `aca7654d20637b3a6d96d3898c155906932543951a6b5585eb548d5064783de6`. The image does not expose the installed build; correlate it with the diagnostic thread rather than guessing from TestFlight availability.

The response header arrived;83,423 declared bytes were not consumed. Root cause is not established by the screenshot. The server currently sends under the default message context and cancels after stack processing. Investigate explicit final-message write-close and remote EOF before teardown under delayed consumption. Existing passing loopback/constrained-window tests do not prove physical-device success.

Preserve the owner's helper, pairing, trust pin and granted corpus. Tests use isolated loopback listeners and temporary identities. No delivered fix, native acceptance, helper replacement or new publication is claimed by this checkpoint.
