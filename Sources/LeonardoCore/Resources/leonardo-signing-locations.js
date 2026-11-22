const leonardoSigningHTMLTokens = /<!--[\s\S]*?(?:-->|$)|<![^>]*>|<(\/?)([A-Za-z][\w:-]*)(?:[^<>"']|"[^"]*"|'[^']*')*>|([^<]+)|</g;

// Named references come from https://html.spec.whatwg.org/entities.json. The bundled table
// keeps the characters for each name, including legacy forms without a semicolon.
const leonardoEntityNameLimit = Math.max(...Object.keys(leonardoSigningHTMLEntities).map(name => name.length));
const leonardoLegacyNumericReferences = [
  0x20ac, 0x81, 0x201a, 0x192, 0x201e, 0x2026, 0x2020, 0x2021,
  0x2c6, 0x2030, 0x160, 0x2039, 0x152, 0x8d, 0x17d, 0x8f,
  0x90, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014,
  0x2dc, 0x2122, 0x161, 0x203a, 0x153, 0x9d, 0x17e, 0x178
];

function decodeLeonardoHTMLText(text, attribute = false) {
  return text.replace(/&(#(?:x[\da-f]+|\d+);?|[a-z][a-z0-9]*;?)/gi, (entity, value, offset) => {
    if (value[0] === "#") {
      const hex = value[1]?.toLowerCase() === "x";
      let scalar = Number.parseInt(value.slice(hex ? 2 : 1), hex ? 16 : 10);
      if (!scalar || scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff)) return "\uFFFD";
      scalar = leonardoLegacyNumericReferences[scalar - 0x80] ?? scalar;
      return String.fromCodePoint(scalar);
    }
    for (let length = Math.min(value.length, leonardoEntityNameLimit); length > 0; length--) {
      const name = value.slice(0, length);
      if (!Object.hasOwn(leonardoSigningHTMLEntities, name)) continue;
      const next = text[offset + length + 1] || "";
      if (attribute && !name.endsWith(";") && /[a-z0-9=]/i.test(next)) return entity;
      return leonardoSigningHTMLEntities[name] + value.slice(length);
    }
    return entity;
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
      const value = decodeLeonardoHTMLText(doubleQuoted ?? singleQuoted ?? unquoted ?? "", true).trim();
      if (!value) continue;
      if (kind === "src") references.push(value);
      else references.push(...leonardoSrcsetURLs(value));
    }
  }
  return references;
}
