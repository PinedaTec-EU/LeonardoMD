# Document extensions

Implementation tracked in [#277](https://github.com/PinedaTec-EU/LeonardoMD/issues/277).

This work adds offline Vega-Lite charts, Citation.js bibliographies and focused
Markdown extensions. The implementation is in progress; syntax and final default
choices will be documented here after integration.

Each engine has a global setting and an inheritable project setting. Disabling
an extension preserves document source. Existing Mermaid and math defaults remain
unchanged. New engines must preserve the preview content security policy and
must not fetch document-authored remote data.
