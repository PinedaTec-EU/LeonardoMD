# Markdown extras

This document demonstrates the optional footnote and callout syntax.

The example is intentionally offline and self-contained.[^local]

> [!NOTE]
> Enable **Markdown extras** in Preferences to render this panel and the note
> at the end of the document.

> [!TIP]
> A second reference can point to the same note.[^local]

## Disclosure without a plugin

<details>
<summary>What is loaded?</summary>

Only the local Markdown extension resource is loaded when the feature is
enabled. No remote service is needed.

</details>

[^local]: This footnote is stored in the Markdown source and remains available
    even when the extension is disabled.
