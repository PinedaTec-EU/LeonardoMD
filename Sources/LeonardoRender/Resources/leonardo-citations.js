(() => {
  "use strict";

  const SOURCE_SELECTOR = [
    "pre > code.language-bibtex",
    "pre > code.language-csl-json"
  ].join(", ");
  const SOURCE_CLASS = "leonardo-citation-source";
  const BIBLIOGRAPHY_CLASS = "leonardo-bibliography";
  const DIAGNOSTIC_CLASS = "leonardo-citation-error";
  const DEFAULT_STYLE = "apa";
  const DEFAULT_LANGUAGE = "en-US";
  const MAX_SOURCE_BYTES = 512 * 1024;
  const MAX_RECORDS = 2_000;
  const MAX_REFERENCES = 1_000;
  const citationPattern = /\[((?:@[A-Za-z0-9][A-Za-z0-9_.:-]*(?:\s*[,;]\s*)?)+)\]/g;
  let enginePromise;
  const renderGenerations = new WeakMap();

  function sourceBytes(value) {
    return new TextEncoder().encode(value).byteLength;
  }

  function beginRender(root) {
    const generation = (renderGenerations.get(root) || 0) + 1;
    renderGenerations.set(root, generation);
    return generation;
  }

  function isCurrentRender(root, generation) {
    return renderGenerations.get(root) === generation;
  }

  function sourceBlocks(root) {
    if (!root || typeof root.querySelectorAll !== "function") return [];
    return Array.from(root.querySelectorAll(SOURCE_SELECTOR)).map((code, index) => {
      const parent = code.parentElement;
      const format = code.classList.contains("language-bibtex") ? "bibtex" : "csl-json";
      if (parent) {
        parent.classList.add(SOURCE_CLASS);
        parent.dataset.citationFormat = format;
        parent.dataset.citationIndex = String(index);
      }
      return { code, parent, format, source: code.textContent || "" };
    });
  }

  function prepare(root, payload) {
    if (!payload || payload.allowsCitations !== true) {
      return { sourceBlocks: 0, citationReferences: 0 };
    }
    const blocks = sourceBlocks(root);
    return {
      sourceBlocks: blocks.length,
      citationReferences: citationReferences(root).length
    };
  }

  function citationReferences(root) {
    if (!root || typeof document === "undefined") return [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const references = [];
    let node;
    while ((node = walker.nextNode())) {
      if (!node.parentElement || excluded(node.parentElement)) continue;
      const value = node.nodeValue || "";
      citationPattern.lastIndex = 0;
      if (citationPattern.test(value)) references.push(node);
    }
    return references;
  }

  function excluded(element) {
    return Boolean(element.closest(
      "pre, code, a, ." + BIBLIOGRAPHY_CLASS + ", .leonardo-citation, .leonardo-citation-error"
    ));
  }

  function citationKeys(value) {
    return Array.from(value.matchAll(/@([A-Za-z0-9][A-Za-z0-9_.:-]*)/g)).map((match) => match[1]);
  }

  function citationEngine(engine) {
    const Cite = engine && (engine.Cite || (engine.default && engine.default.Cite));
    if (typeof Cite !== "function") {
      throw new Error("Citation.js engine is unavailable.");
    }
    return Cite;
  }

  function recordsFromCite(cite) {
    if (Array.isArray(cite && cite.data)) return cite.data;
    if (cite && typeof cite.get === "function") {
      const data = cite.get({ type: "json" });
      if (Array.isArray(data)) return data;
    }
    throw new Error("Citation.js returned no bibliographic records.");
  }

  function parseRecords(Cite, blocks) {
    const records = [];
    const seen = new Set();
    let totalSourceBytes = 0;
    blocks.forEach(({ format, source }) => {
      totalSourceBytes += sourceBytes(source);
      if (totalSourceBytes > MAX_SOURCE_BYTES) {
        throw new Error("The citation source exceeds the 512 KiB limit.");
      }
      let input = source;
      if (format === "csl-json") {
        try {
          input = JSON.parse(source);
        } catch (_) {
          throw new Error("The CSL-JSON citation block contains invalid JSON.");
        }
      }
      if (format === "csl-json") {
        const values = Array.isArray(input) ? input : [input];
        if (!values.every(value => value && typeof value === "object" && !Array.isArray(value))) {
          throw new Error("CSL-JSON must contain bibliographic objects, not identifiers or URLs.");
        }
      }
      // Bypass format autodetection: Citation.js core also knows a generic URL
      // input type. A bibliography fence must never select a remote resolver.
      const forceType = format === "bibtex" ? "@bibtex/text" :
        (Array.isArray(input) ? "@csl/list+object" : "@csl/object");
      const cite = new Cite(input, { forceType });
      recordsFromCite(cite).forEach((record) => {
        const id = String(record.id || record._id || "").trim();
        if (!id) throw new Error("A citation record is missing its id.");
        if (seen.has(id)) throw new Error(`Duplicate citation key: ${id}`);
        seen.add(id);
        records.push(record);
        if (records.length > MAX_RECORDS) throw new Error("The citation source contains too many records.");
      });
    });
    if (records.length === 0) throw new Error("The citation block contains no records.");
    return records;
  }

  function sanitizedHTML(value) {
    const purifier = globalThis.DOMPurify;
    if (!purifier || typeof purifier.sanitize !== "function") {
      throw new Error("Citation output sanitizer is unavailable.");
    }
    return purifier.sanitize(String(value || ""), {
      USE_PROFILES: { html: true },
      FORBID_TAGS: ["script", "style", "iframe", "object", "embed", "form"],
      FORBID_ATTR: ["href", "src", "srcdoc", "action", "formaction", "xlink:href"]
    });
  }

  function formatCitation(Cite, records, keys, options) {
    const uniqueKeys = [...new Set(keys)];
    const selected = records.filter((record) => uniqueKeys.includes(String(record.id)));
    if (selected.length !== uniqueKeys.length) {
      const missing = uniqueKeys.filter((key) => !records.some((record) => String(record.id) === key));
      return { html: "", missing };
    }
    const cite = new Cite(selected);
    const html = cite.format("citation", {
      format: "html",
      style: options.style,
      lang: options.lang,
      link: false
    });
    return { html: sanitizedHTML(html), missing: [] };
  }

  function formatBibliography(Cite, records, options) {
    const cite = new Cite(records);
    const html = cite.format("bibliography", {
      format: "html",
      style: options.style,
      lang: options.lang,
      link: false
    });
    const safe = sanitizedHTML(html);
    if (!safe.trim()) throw new Error("Citation.js returned an empty bibliography.");
    return safe;
  }

  function makeImmutable(element) {
    const editable = element.closest("[data-leonardo-edit]");
    if (!editable) return;
    editable.removeAttribute("data-leonardo-edit");
    editable.removeAttribute("data-leonardo-render");
    editable.contentEditable = "false";
    editable.setAttribute("aria-readonly", "true");
  }

  function replaceCitations(root, Cite, records, options) {
    const nodes = citationReferences(root);
    if (nodes.length > MAX_REFERENCES) {
      throw new Error("The document contains too many citation references.");
    }
    const missing = [];
    nodes.forEach((textNode) => {
      makeImmutable(textNode.parentElement);
      const value = textNode.nodeValue || "";
      citationPattern.lastIndex = 0;
      let cursor = 0;
      let match;
      const fragment = document.createDocumentFragment();
      while ((match = citationPattern.exec(value)) !== null) {
        if (match.index > cursor) fragment.appendChild(document.createTextNode(value.slice(cursor, match.index)));
        const keys = citationKeys(match[1]);
        const result = formatCitation(Cite, records, keys, options);
        const span = document.createElement("span");
        span.className = "leonardo-citation";
        span.dataset.citationKeys = keys.join(" ");
        if (result.missing.length > 0) {
          span.classList.add("leonardo-citation-missing");
          span.textContent = `[?${result.missing.join(", ?")}]`;
          result.missing.forEach((key) => { if (!missing.includes(key)) missing.push(key); });
        } else {
          span.innerHTML = result.html;
        }
        makeImmutable(span);
        fragment.appendChild(span);
        cursor = match.index + match[0].length;
      }
      if (cursor < value.length) fragment.appendChild(document.createTextNode(value.slice(cursor)));
      if (fragment.childNodes.length > 0) textNode.parentNode.replaceChild(fragment, textNode);
    });
    return missing;
  }

  function appendBibliography(root, lastSource, html, payload) {
    const section = document.createElement("section");
    section.className = BIBLIOGRAPHY_CLASS;
    section.setAttribute("aria-label", payload.citationBibliographyTitle || "References");
    const heading = document.createElement("h2");
    heading.textContent = payload.citationBibliographyTitle || "References";
    section.appendChild(heading);
    const body = document.createElement("div");
    body.className = "leonardo-bibliography-body";
    body.innerHTML = html;
    section.appendChild(body);
    if (lastSource && lastSource.parentNode) {
      lastSource.parentNode.insertBefore(section, lastSource.nextSibling);
    } else {
      root.appendChild(section);
    }
    return section;
  }

  function hideSources(blocks) {
    blocks.forEach(({ parent }) => {
      if (!parent) return;
      parent.hidden = true;
      parent.setAttribute("aria-hidden", "true");
      parent.classList.add("leonardo-citation-source-hidden");
    });
  }

  function showDiagnostic(root, blocks, message) {
    const diagnostic = document.createElement("aside");
    diagnostic.className = DIAGNOSTIC_CLASS;
    diagnostic.setAttribute("role", "alert");
    diagnostic.textContent = message;
    const target = blocks[blocks.length - 1] && blocks[blocks.length - 1].parent;
    if (target && target.parentNode) target.parentNode.insertBefore(diagnostic, target.nextSibling);
    else root.prepend(diagnostic);
    return diagnostic;
  }

  async function render(root, payload, options = {}) {
    const generation = root ? beginRender(root) : undefined;
    if (!root || !payload || payload.allowsCitations !== true) {
      return { rendered: false, reason: "disabled", sourceBlocks: 0, citationReferences: 0 };
    }
    const blocks = sourceBlocks(root);
    if (blocks.length === 0) {
      return { rendered: false, reason: "no-source", sourceBlocks: 0, citationReferences: citationReferences(root).length };
    }
    const loadEngine = options.loadEngine;
    if (typeof loadEngine !== "function") {
      showDiagnostic(root, blocks, "Citations could not be rendered because the Citation.js loader is unavailable.");
      return { rendered: false, reason: "loader-unavailable", sourceBlocks: blocks.length };
    }
    try {
      if (!enginePromise) {
        enginePromise = Promise.resolve().then(() => loadEngine());
        enginePromise.catch(() => { enginePromise = undefined; });
      }
      const engine = await enginePromise;
      if (!isCurrentRender(root, generation)) {
        return { rendered: false, reason: "stale", sourceBlocks: blocks.length };
      }
      const Cite = citationEngine(engine || globalThis.LeonardoCitationEngine);
      const records = parseRecords(Cite, blocks);
      const formatOptions = {
        style: payload.citationStyle || DEFAULT_STYLE,
        lang: payload.citationLanguage || DEFAULT_LANGUAGE
      };
      const missing = replaceCitations(root, Cite, records, formatOptions);
      const bibliography = formatBibliography(Cite, records, formatOptions);
      appendBibliography(root, blocks[blocks.length - 1].parent, bibliography, payload);
      hideSources(blocks);
      if (missing.length > 0) {
        showDiagnostic(root, blocks, `Citation key not found: ${missing.join(", ")}`);
      }
      return {
        rendered: true,
        sourceBlocks: blocks.length,
        citationReferences: citationReferences(root).length,
        missingKeys: missing
      };
    } catch (error) {
      if (!isCurrentRender(root, generation)) {
        return { rendered: false, reason: "stale", sourceBlocks: blocks.length };
      }
      const message = error && error.message ? error.message : "Citations could not be rendered.";
      showDiagnostic(root, blocks, message);
      return { rendered: false, reason: "render-error", sourceBlocks: blocks.length, error: message };
    }
  }

  globalThis.LeonardoCitations = Object.freeze({ prepare, render });
})();
