# MDLZ archive safety

The bundled helper applies the following boundary before it reads or writes
archive content:

- member names use canonical POSIX relative paths; absolute paths, drive
  prefixes, NUL bytes, backslashes, `.`/empty components, and `..` components
  are rejected;
- normalized Unicode and case-folded names may not collide;
- ZIP symlinks and special file types are rejected, including entries encoded
  through external file attributes;
- member count, uncompressed member size, total size, and suspicious
  compression ratios are bounded before extraction;
- exactly one root `.mdlf` or `.mdlr` is required; non-document files belong
  under `assets/`;
- extraction writes into a new sibling directory and creates files without
  replacement, so a failed extraction cannot overwrite an existing folder;
- packing refuses source symlinks, missing roots, multiple documents, and an
  existing output; entries are sorted and use stable timestamps for repeatable
  output;
- a failed validation never changes the source archive or source directory.

These checks contain archive transport hazards only. They do not make Markdown,
HTML, SVG, regular expressions, or other document payloads executable or safe
to evaluate. Hosts must keep their normal rendering sanitization and should
only use the shared schema to validate declarative values.
