# Open questions

- Non-macOS UIs require separate product work. Signed public distribution is available as [0.1.64](https://github.com/PinedaTec-EU/LeonardoMD/releases/tag/v0.1.64); hosted update/install/relaunch acceptance stays open in [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15).
- Arbitrary executable third-party plugins require a permission and signing design; bundled extensions are the initial catalog.
- Performance targets in US.000011 are acceptance budgets; report measured evidence, not assumed compliance from architecture.

- Historical [#9](https://github.com/PinedaTec-EU/LeonardoMD/issues/9) and [#31](https://github.com/PinedaTec-EU/LeonardoMD/issues/31) root causes remain unproven. Both reports were closed at the owner's request after current-version non-reproduction on 2026-10-08 (0.1.0 build 1, main `041c63b`): first-panel opening passed in two fresh processes and startup passed through LaunchServices and direct execution in the unrestricted agent context. These observations do not prove every activation state or restricted sandbox is unaffected; preserve that scope if a new report occurs.

- Central automatic merge cannot mint its scoped token until the installation accepts `statuses: read`: [pinedatec-ci#279](https://github.com/PinedaTec-EU/pinedatec-ci/issues/279). Policy dispatch, immutable engine access, required-check binding and serial materialization are verified. The protected owner merge path remains available; do not claim central automatic merge succeeded.
