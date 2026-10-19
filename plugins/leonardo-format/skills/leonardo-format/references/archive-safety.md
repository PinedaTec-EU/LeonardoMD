# MDLZ archive safety

The bundled helper applies the following boundary before it reads or writes
archive content:

- its limits match the host transport envelope: at most 64 MiB of ZIP bytes,
  2,048 entries, and 32 MiB of expanded content in total or for any one
  member; it additionally rejects compression ratios above 500 for members of
  at least 64 KiB;
- member names use canonical POSIX relative paths; absolute paths, drive
  prefixes, NUL bytes, backslashes, `.`/empty components, and `..` components
  are rejected;
- normalized Unicode and case-folded names may not collide;
- ZIP symlinks and special file types are rejected, including entries encoded
  through external file attributes;
- only ZIP Stored and raw DEFLATE entries are accepted, matching the native
  Leonardo reader;
- member count, uncompressed member size, total size, and suspicious
  compression ratios are bounded before extraction;
- exactly one root `.mdlf` or `.mdlr` is required; non-document files belong
  under `assets/`;
- directory records are validated for safe paths but are transport noise: they
  are ignored by `inspect` and `extract`, and `pack` does not emit them;
- the root document is parsed, version-checked, duplicate-key checked and
  validated against the bundled v1 schema before `inspect` reports results,
  `extract` creates a directory, or `pack` writes an archive;
- extraction writes into a new sibling directory and creates files without
  replacement, so a failed extraction cannot overwrite an existing folder;
- packing refuses source symlinks, missing roots, multiple documents, and an
  existing output; entries are sorted and use stable timestamps for repeatable
  output;
- a failed validation never changes the source archive or source directory.

These checks contain archive transport hazards and the root document's
declarative definition safety rules. They do not make Markdown, HTML, SVG,
regular expressions, or other document payloads executable or safe to evaluate.
Hosts must keep their normal rendering sanitization; current form values remain
opaque draft data.
