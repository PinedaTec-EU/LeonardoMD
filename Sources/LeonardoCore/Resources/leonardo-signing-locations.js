const leonardoSigningHTMLTokens = /<!--[\s\S]*?(?:-->|$)|<![^>]*>|<(\/?)([A-Za-z][\w:-]*)(?:[^<>"']|"[^"]*"|'[^']*')*>|([^<]+)|</g;

const leonardoSigningHTMLEntities = {
  lbrace: "{", lcub: "{", rbrace: "}", rcub: "}",
  colon: ":", lowbar: "_", period: ".", nbsp: " ", Tab: "\t", NewLine: "\n"
};

function decodeLeonardoHTMLText(text) {
  return text.replace(/&(#x[\da-f]+|#\d+|[a-z][a-z0-9]+);/gi, (entity, value) => {
    if (value[0] !== "#") return Object.hasOwn(leonardoSigningHTMLEntities, value)
      ? leonardoSigningHTMLEntities[value] : entity;
    const hex = value[1]?.toLowerCase() === "x";
    const scalar = Number.parseInt(value.slice(hex ? 2 : 1), hex ? 16 : 10);
    return scalar <= 0x10ffff ? String.fromCodePoint(scalar) : entity;
  });
}

function leonardoVisibleRubrics(markdown, probe, fieldIDs, prefix) {
  "use strict";
  const options = { gfm: true, breaks: false };
  const fields = new Set(fieldIDs);
  const fieldPattern = /\{\{\s*field:([A-Za-z][A-Za-z0-9_.-]{0,63})\s*\}\}/g;
  const literalTags = new Set(["code", "pre", "script", "style", "template", "textarea", "title"]);
  // Marked has already resolved Markdown containers, links, and code.
  // Walk its HTML text without inspecting attribute values or comments.
  // Skip literal subtrees as the production form renderer does.
  function textFields(html) {
    const openLiterals = [];
    const visible = [];
    for (const [, closing, rawTag, text] of html.matchAll(leonardoSigningHTMLTokens)) {
      if (rawTag) {
        const tag = rawTag.toLowerCase();
        if (!literalTags.has(tag)) continue;
        if (!closing) {
          openLiterals.push(tag);
        } else {
          const index = openLiterals.lastIndexOf(tag);
          if (index >= 0) openLiterals.length = index;
        }
      } else if (text && openLiterals.length === 0) {
        for (const match of decodeLeonardoHTMLText(text).matchAll(fieldPattern)) visible.push(match[1]);
      }
    }
    return visible;
  }

  const original = textFields(marked.parse(markdown, options)).filter(field => fields.has(field));
  const ordinals = textFields(marked.parse(probe.text, options))
    .filter(field => field.startsWith(prefix))
    .map(field => Number(field.slice(prefix.length)))
    .filter(index => Number.isSafeInteger(index) && fields.has(probe.ids[index]));
  // A visible control that cannot be traced back to one literal source token
  // cannot be safely bound to a signed location.
  if (ordinals.length !== original.length || new Set(ordinals).size !== ordinals.length ||
      original.some((field, index) => probe.ids[ordinals[index]] !== field) ||
      ordinals.some((ordinal, index) => index > 0 && ordinal <= ordinals[index - 1])) return null;
  return ordinals;
}

function leonardoSrcsetURLs(value) {
  const urls = [];
  let remaining = value;
  while ((remaining = remaining.replace(/^[,\t\n\f\r ]+/, ""))) {
    const [url] = /^[^\t\n\f\r ]+/.exec(remaining);
    remaining = remaining.slice(url.length);
    urls.push(url.replace(/,+$/, ""));
    // A comma attached to a URL ends a descriptorless candidate. Otherwise
    // skip the width or density descriptor, leaving commas inside URLs intact.
    if (!url.endsWith(",")) {
      const separator = remaining.indexOf(",");
      remaining = separator < 0 ? "" : remaining.slice(separator + 1);
    }
  }
  return urls;
}

function leonardoSigningImageReferences(markdown) {
  "use strict";
  const html = marked.parse(markdown, { gfm: true, breaks: false });
  const attribute = /[\t\n\f\r ]+([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;
  const references = [];
  for (const [raw, closing, tag] of html.matchAll(leonardoSigningHTMLTokens)) {
    if (closing) continue;
    const element = tag?.toLowerCase();
    if (element !== "img" && element !== "source") continue;
    for (const [, name, doubleQuoted, singleQuoted, unquoted] of raw.matchAll(attribute)) {
      const kind = name.toLowerCase();
      if (kind !== "srcset" && (kind !== "src" || element !== "img")) continue;
      const value = decodeLeonardoHTMLText(doubleQuoted ?? singleQuoted ?? unquoted ?? "").trim();
      if (!value) continue;
      if (kind === "src") references.push(value);
      else references.push(...leonardoSrcsetURLs(value));
    }
  }
  return references;
}
