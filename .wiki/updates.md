# Application updates

`ApplicationUpdates` owns Sparkle 2.9.6 and native menu actions; Sparkle persists check preferences. No public signing key means an explanatory development dialog. Primary instances alone start Sparkle; installation uses the application termination guard covering all document tabs.

`scripts/configure-update-bundle.py` validates version/channel, positive numeric build and HTTPS feed. `prepare-release.sh` embeds helpers, signs inside out, notarizes and generates signed assets; beta-only local candidates may explicitly skip notarization. `verify-update-archive.py` checks real archive bytes with Sparkle. Beta and stable share one increasing build sequence but use separate feeds and Keychain keys. See [release contract](../doc/releases.md). Publication and hosted end-to-end acceptance remain pending for [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15), PR #17.
