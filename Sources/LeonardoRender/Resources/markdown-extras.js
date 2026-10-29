(() => {
  "use strict";

  // The extension is deliberately small and parser-only.  The host owns the
  // Marked instance (including table annotations); this module only adds the
  // two source syntaxes that Leonardo advertises as Markdown extras.
  const definitionPattern = /^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)(?:\n|$)((?:(?: {2,4}|\t).*(?:\n|$))*)/;
  const referencePattern = /^\[\^([^\]\s]+)\]/;
  const calloutPattern = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*/i;
  const calloutLabels = {
    NOTE: "Note",
    TIP: "Tip",
    IMPORTANT: "Important",
    WARNING: "Warning",
    CAUTION: "Caution"
  };

  let installedParser = null;
  let activeParser = null;
  let source = "";
  let collectedTokens = null;
  let definitions = new Map();
  let references = [];
  let nextReferenceNumber = 0;

  function escapeHTML(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function normalizedID(value) {
    const normalized = String(value).toLowerCase().replace(/[^a-z0-9_-]+/g, "-")
      .replace(/^-+|-+$/g, "");
    return normalized || "note";
  }

  function identifier(value) {
    // Keep the visible source label out of the HTML identifier's trust
    // boundary while retaining deterministic, readable anchors.
    const raw = String(value);
    let hash = 2166136261;
    for (let index = 0; index < raw.length; index += 1) {
      hash ^= raw.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return `${normalizedID(raw)}-${(hash >>> 0).toString(16)}`;
  }

  function definitionBody(raw) {
    const firstLine = raw[2];
    const continuation = raw[3] || "";
    const lines = continuation.split("\n").filter((line, index, all) => line !== "" || index < all.length - 1);
    const continuationText = lines
      .map((line) => line.replace(/^(?: {2,4}|\t)/, ""))
      .join("\n");
    return continuationText ? `${firstLine}\n${continuationText}` : firstLine;
  }

  function visitTokens(tokens, callback) {
    for (const token of tokens || []) {
      callback(token);
      if (token.tokens) visitTokens(token.tokens, callback);
      if (token.items) {
        for (const item of token.items) visitTokens(item.tokens, callback);
      }
      if (token.header) {
        for (const cell of token.header) visitTokens(cell.tokens, callback);
      }
      if (token.rows) {
        for (const row of token.rows) {
          for (const cell of row) visitTokens(cell.tokens, callback);
        }
      }
      // Footnote definitions intentionally keep their inline children in a
      // private property so preview editing cannot make them contenteditable.
      if (token.bodyTokens) visitTokens(token.bodyTokens, callback);
    }
  }

  function collect(tokens) {
    if (!Array.isArray(tokens) || tokens === collectedTokens) return tokens;
    collectedTokens = tokens;
    definitions = new Map();
    references = [];
    nextReferenceNumber = 0;

    visitTokens(tokens, (token) => {
      if (token.type === "leonardo-footnote-definition" && !definitions.has(token.id)) {
        definitions.set(token.id, {
          token,
          anchor: identifier(token.id),
          number: 0,
          references: []
        });
      }
    });

    visitTokens(tokens, (token) => {
      if (token.type !== "leonardo-footnote-reference") return;
      const definition = definitions.get(token.id);
      if (!definition) return;
      if (!definition.number) definition.number = ++nextReferenceNumber;
      const referenceIndex = definition.references.length + 1;
      const reference = { token, definition, referenceIndex };
      definition.references.push(reference);
      references.push(reference);
      token.number = definition.number;
      token.referenceIndex = referenceIndex;
    });
    return tokens;
  }

  function renderFootnoteReference(token) {
    const definition = definitions.get(token.id);
    if (!definition || !token.number) {
      return escapeHTML(token.raw || `[^${token.id}]`);
    }
    const referenceID = `fnref-${definition.anchor}-${token.referenceIndex}`;
    const noteID = `fn-${definition.anchor}`;
    return `<sup class="markdown-footnote-ref" id="${referenceID}"><a href="#${noteID}" aria-describedby="markdown-footnotes-title">${token.number}</a></sup>`;
  }

  function renderFootnoteSection() {
    if (!references.length || !activeParser) return "";
    const used = [];
    const seen = new Set();
    for (const reference of references) {
      if (seen.has(reference.definition)) continue;
      seen.add(reference.definition);
      used.push(reference.definition);
    }
    const items = used.map((definition) => {
      const bodyTokens = definition.token.bodyTokens || [];
      const body = activeParser.Parser.parseInline(bodyTokens, activeParser.defaults);
      const backrefs = definition.references.map((reference) => {
        const referenceID = `fnref-${definition.anchor}-${reference.referenceIndex}`;
        const label = definition.references.length > 1
          ? `Back to reference ${definition.number}, occurrence ${reference.referenceIndex}`
          : `Back to reference ${definition.number}`;
        return `<a class="markdown-footnote-backref" href="#${referenceID}" aria-label="${escapeHTML(label)}">↩︎</a>`;
      }).join(" ");
      return `<li id="fn-${definition.anchor}"><p>${body} ${backrefs}</p></li>`;
    }).join("\n");
    return `<section class="markdown-footnotes" aria-labelledby="markdown-footnotes-title"><h2 id="markdown-footnotes-title">Footnotes</h2><ol>${items}</ol></section>`;
  }

  function renderCallout(token) {
    const first = token.tokens?.[0];
    const text = first?.type === "paragraph" ? String(first.text || "") : "";
    const marker = text.match(calloutPattern);
    if (!marker) return false;

    const kind = marker[1].toLowerCase();
    const label = calloutLabels[marker[1].toUpperCase()] || marker[1];
    // Marked has already parsed and escaped the body.  Removing only the
    // fixed marker from the beginning of the first generated paragraph keeps
    // all authored Markdown and nested blocks intact.
    const body = this.parser.parse(token.tokens);
    const markerHTML = new RegExp(`^(\\s*<p>\\s*)\\[!${marker[1]}\\][ \\t]*`, "i");
    const cleanedBody = body
      // The marker is part of the source range for the first paragraph.  A
      // generated callout must therefore stay immutable in preview editing;
      // otherwise editing its visible body would accidentally delete the
      // `[!TYPE]` marker. The raw editor remains authoritative for the block.
      .replace(/<span data-leonardo-render="[^"]*" data-leonardo-edit="\d+">([\s\S]*?)<\/span>/g, "$1")
      .replace(markerHTML, "$1");
    return `<aside class="markdown-callout markdown-callout-${kind}" data-callout="${kind}" role="note" aria-label="${escapeHTML(label)}"><p class="markdown-callout-title">${escapeHTML(label)}</p>${cleanedBody}</aside>\n`;
  }

  function install(parser) {
    if (!parser || typeof parser.use !== "function") return parser;
    if (installedParser === parser) return parser;
    installedParser = parser;
    activeParser = parser;
    parser.use({
      extensions: [
        {
          name: "leonardo-footnote-definition",
          level: "block",
          start(src) {
            const match = /\n {0,3}\[\^[^\]\s]+\]:/.exec(src);
            return match ? match.index : undefined;
          },
          tokenizer(src) {
            const match = definitionPattern.exec(src);
            if (!match) return false;
            const body = definitionBody(match);
            return {
              type: "leonardo-footnote-definition",
              raw: match[0],
              id: match[1],
              text: body,
              // Keep this outside `tokens`: preview-editing deliberately
              // treats generated footnote content as immutable output.
              bodyTokens: this.lexer.inlineTokens(body)
            };
          },
          renderer() { return ""; }
        },
        {
          name: "leonardo-footnote-reference",
          level: "inline",
          start(src) {
            const match = /\[\^[^\]\s]+\]/.exec(src);
            return match ? match.index : undefined;
          },
          tokenizer(src) {
            const match = referencePattern.exec(src);
            if (!match) return false;
            return {
              type: "leonardo-footnote-reference",
              raw: match[0],
              id: match[1]
            };
          },
          renderer(token) { return renderFootnoteReference(token); }
        }
      ],
      renderer: {
        blockquote(token) { return renderCallout.call(this, token); }
      },
      hooks: {
        processAllTokens(tokens) { return collect(tokens); }
      }
    });
    return parser;
  }

  function beginDocument(markdown) {
    source = typeof markdown === "string" ? markdown : "";
    collectedTokens = null;
    definitions = new Map();
    references = [];
    nextReferenceNumber = 0;
  }

  function finish(html) {
    const rendered = typeof html === "string" ? html : "";
    const section = renderFootnoteSection();
    return section ? `${rendered}\n${section}\n` : rendered;
  }

  window.LeonardoMarkdownExtras = {
    install,
    beginDocument,
    collect,
    finish
  };
})();
