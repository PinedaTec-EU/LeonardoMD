# Open questions

- Non-macOS UIs require separate product work. Signed public distribution is available as [0.1.64](https://github.com/PinedaTec-EU/LeonardoMD/releases/tag/v0.1.64); hosted update/install/relaunch acceptance stays open in [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15).
- Arbitrary executable third-party plugins require a permission and signing design; bundled extensions are the initial catalog.
- Performance targets in US.000011 are acceptance budgets; report measured evidence, not assumed compliance from architecture.

- Historical [#9](https://github.com/PinedaTec-EU/LeonardoMD/issues/9) and [#31](https://github.com/PinedaTec-EU/LeonardoMD/issues/31) root causes remain unproven. Both reports were closed at the owner's request after current-version non-reproduction on 2026-10-08 (0.1.0 build 1, main `041c63b`): first-panel opening passed in two fresh processes and startup passed through LaunchServices and direct execution in the unrestricted agent context. These observations do not prove every activation state or restricted sandbox is unaffected; preserve that scope if a new report occurs.

- The legacy generated-PR permission gap [pinedatec-ci#279](https://github.com/PinedaTec-EU/pinedatec-ci/issues/279) is closed. The automatic App writer has materialized version/prepared notes on main; verify a subsequent source merge through its consumer dispatch, correlated central run and actual writes for LeonardoMD acceptance under [central #294](https://github.com/PinedaTec-EU/pinedatec-ci/issues/294). Main remains unprotected by owner policy; exact-head tests, App-owned policy and strict independent judgment remain mandatory process gates ([#81](https://github.com/PinedaTec-EU/LeonardoMD/issues/81)).
