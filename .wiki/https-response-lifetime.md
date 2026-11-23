# HTTPS response lifetime

[#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380), candidate [PR #392](https://github.com/PinedaTec-EU/LeonardoMD/pull/392).

- Physical LL1: HTTP200,409481/492904 bytes, URLError-1005. This is an interrupted body, not an auth rejection or a successful transfer. Root cause remains unconfirmed.
- Strict pinned Python EOF/delayed-window probes and iOS27.0 Simulator baseline pass unchanged server code. The simulator's LAN-address route is `lo0`; no physical Wi-Fi claim.
- Candidate: final TLS write-stream context, bounded five-second peer-close grace, original request/response/stop cancellation retained.16 held-open peers must not exhaust admission slots.
- LLS1 completion facts exclude addresses, paths, business IDs, credentials, payload and arbitrary error descriptions. `sendProcessed`/`peerClosed` never mean app-level delivery.
- Little Leonardo follow-up under [#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380): user alerts carry a short localized message and an opaque `LL-…` reference; **Ajustes de sincronización → Ver log** shows the matching recent local entry. `MobileDiagnosticLog` keeps at most 120 entries/64 KiB and records only the bounded LL1 transport facts or a safe error domain/code. It does not send the log. This UI change does not prove the physical image-transfer cause is fixed.
- No helper installation, pin/grant changes or physical success; keep #380 open until the original physical case passes. See [evidence and acceptance](../doc/validation/https-response-lifetime/README.md).

- 7 November checkpoint: signed QA392 launched and quit normally; scoped preferences/practice originals restored3/3. Help EN passed; ES acceptance partial due intermittent thumbnail captures. CI rejected slow-probe30s and16-peer startup10s deadlines. Canonical392 was never activated; original helper was restored and verified (port/pin/grants unchanged). Diagnostic test-only timing pass pending, no physical resolution claimed.
