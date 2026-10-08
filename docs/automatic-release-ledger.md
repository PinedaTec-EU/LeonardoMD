# Automatic central release ledger

This opted-in consumer uses the common [central writer contract](https://github.com/PinedaTec-EU/pinedatec-ci/blob/main/docs/private-release-ledger-publisher.md).
After a source PR merges into main, the checkout-free adapter requests operation
`all` using the existing `PINEDATEC_CI_DISPATCH_TOKEN`. The central catalog remains
the activation boundary. The schedule recovers missed requests.

The central App drains pending entries in integration order and atomically writes
the version, checkpoint, consumed entry deletion, declared version manifests and
prepared notes to main. Product CI and review belong to the source PR; automatic
metadata updates create no PR and use `[skip ci]`. Branch protection remains
respected. There is no manual generated-PR review/draft transition in this path.

Prepared notes insert `.prepared` before the configured notes file suffix (for
example `deploy/release-notes.prepared.md`). These describe materialized changes
without claiming publication. Accepted notes stay at the configured notes path
and still require verified publication/deployment evidence. Builds may package
prepared notes alongside the version; a calculation is not deployment.

Legacy open automation PRs must be reconciled against main before merging; never
consume their entries again. Source policy validation, product CI, immutable
deployment tags and publication evidence are retained. SynaptIQT remains separate.

Central tracking: [#294](https://github.com/PinedaTec-EU/pinedatec-ci/issues/294).
Consumer tracking: [#69](https://github.com/PinedaTec-EU/LeonardoMD/issues/69).
