# Open questions

- Public distribution/notarization and non-macOS UIs require separate release work.
- Arbitrary executable third-party plugins require a permission and signing design; bundled extensions are the initial catalog.
- Performance targets in US.000011 are acceptance budgets; report measured evidence, not assumed compliance from architecture.

- Historical [#9](https://github.com/PinedaTec-EU/LeonardoMD/issues/9) and [#31](https://github.com/PinedaTec-EU/LeonardoMD/issues/31) root causes remain unproven. Both reports were closed at the owner's request after current-version non-reproduction on 2026-10-08 (0.1.0 build 1, main `041c63b`): first-panel opening passed in two fresh processes and startup passed through LaunchServices and direct execution in the unrestricted agent context. These observations do not prove every activation state or restricted sandbox is unaffected; preserve that scope if a new report occurs.

- Release-ledger activation: provision read-only engine access for the trusted policy job and verify branch-rule binding; automatic writers need central public-target support and App registration. Local operator use is available. [#38](https://github.com/PinedaTec-EU/LeonardoMD/issues/38); [contract](../doc/release-version-ledger.md).
