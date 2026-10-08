# Application updates

`ApplicationUpdates` owns Sparkle 2.9.6 and native menu actions; Sparkle persists check preferences. No public signing key means an explanatory development dialog. Primary instances alone start Sparkle; installation uses the application termination guard covering all document tabs.

`scripts/configure-update-bundle.py` validates version/channel, positive numeric build and HTTPS feed. `prepare-release.sh` embeds helpers, signs inside out, notarizes and generates signed assets; beta-only local candidates may explicitly skip notarization. `verify-update-archive.py` checks real archive bytes with Sparkle. Beta and stable share one increasing build sequence but use separate feeds and Keychain keys. See [release contract](../doc/releases.md). Publication and hosted end-to-end acceptance remain pending for [#15](https://github.com/PinedaTec-EU/LeonardoMD/issues/15), PR #17.

Appcast CLI arguments are constructed in `generate-release-appcast.sh` with a nonempty array for system Bash 3.2 compatibility; stable/beta and invalid-channel subprocess regressions cover [#44](https://github.com/PinedaTec-EU/LeonardoMD/issues/44).

Stable appcasts must omit explicit channel tags; known stable/beta feed URLs cannot be assigned to the opposite bundle channel. Negative regressions track [#45](https://github.com/PinedaTec-EU/LeonardoMD/issues/45).

Release preparation compares the bundle public update key against the existing Keychain signing account before signing or generating release assets. Feed paths must use canonical unescaped URLs; encoded or dot-segment aliases are rejected before bundle metadata changes.

Owner convention (#53): visible and packaged versions are numeric `release.feature.build` for every channel. Channel identity stays in updater/feed metadata; beta/alpha suffixes are rejected.

PR #54 also restores marker-stripping protection with mandatory internal publication-channel metadata; regression tracked by #72 (https://github.com/PinedaTec-EU/LeonardoMD/issues/72).
