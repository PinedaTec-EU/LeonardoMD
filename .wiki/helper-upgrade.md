# Synchronization helper upgrade

Canonical bug: [#412](https://github.com/PinedaTec-EU/LeonardoMD/issues/412).
Corrective PR: [#413](https://github.com/PinedaTec-EU/LeonardoMD/pull/413).

The independent launchd helper survives closing/updating the editor. Enabled
registration and healthy legacy XPC do not prove it runs the installed build.
1215 source-update errors were caused by1136 still serving; normal master OFF/ON
loaded installed1215 and owner confirmed paired project/file access without pairing.

The corrective candidate captures build/bundle identity once at helper launch,
adds it compatibly to authenticated health, and renews older/obsolete registration
through existing safe stop/unregister barriers. Never downgrade a newer helper.
A durable preferences upgrade token temporarily denies helper work while retaining
existing consent across failure/crash. Atomic manual consent clears that token,
so late upgrade completion cannot re-enable a user-disabled service. Existing
pairings, source selection, TLS identity and pending application leases remain owned
by their current stores. Missing/newer health stays separate from operational readiness.

Guide37 is reserved for413; personal34/35/36 already exist from other work and
must not be overwritten. Compare actual bundled/personal hashes before acceptance.
