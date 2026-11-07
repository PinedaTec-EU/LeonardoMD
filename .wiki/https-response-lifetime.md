# HTTPS response lifetime

[#380](https://github.com/PinedaTec-EU/LeonardoMD/issues/380), candidate [PR #392](https://github.com/PinedaTec-EU/LeonardoMD/pull/392).

- Physical LL1: HTTP200,409481/492904 bytes, URLError-1005. This is an interrupted body, not an auth rejection or a successful transfer. Root cause remains unconfirmed.
- Strict pinned Python EOF/delayed-window probes and iOS27.0 Simulator baseline pass unchanged server code. The simulator's LAN-address route is `lo0`; no physical Wi-Fi claim.
- Candidate: final TLS write-stream context, bounded five-second peer-close grace, original request/response/stop cancellation retained.16 held-open peers must not exhaust admission slots.
- LLS1 completion facts exclude addresses, paths, business IDs, credentials, payload and arbitrary error descriptions. `sendProcessed`/`peerClosed` never mean app-level delivery.
- No helper installation, pin/grant changes or physical success; keep #380 open until the original physical case passes. See [evidence and acceptance](../doc/validation/https-response-lifetime/README.md).
