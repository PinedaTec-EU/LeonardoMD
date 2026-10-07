# Final-head executable provenance

Reviewed source: `8034f1dec39337cb37d6d5778907ee4c590d9b5c`.

After the final packaging-only correction, prepare-release.sh rebuilt the application from this exact source and produced beta0.1.1-beta.4/build5. DeveloperID and Ed25519 verification passed, including the embedded-key/account guard. Twelve packaging regressions and94 Swift tests passed.

The source executable UUID is still `008B889B-4808-3F2A-A1D6-27373D4BC1B0`, and `otool -s __TEXT __text` output (omit first path line) SHA256 remains `e122f9ffe85a1af812b92004fbb412873338a478738e03475aea85c3840c2e84`, matching the running fixture used for all author captures in ../c9783e6/ and ../4f276a6/. No application source, framework, UI or document guard has changed between these source heads; only packaging script URL validation and tests changed after c9783e6. Thus those attached captures exercise the exact executable code of this final head. Capture dates/states/native viewport/reproduction and raw PNG hashes are in the linked directories; no new capture date is claimed.

Final beta ZIP SHA256: `c0f955c137c63fda88d27bc530ba78ccbc86f8b14938e959feb8696f548caa6b`. Not notarized; no public feed, release or tag published. Public distribution acceptance remains pending outside premerge scope.
