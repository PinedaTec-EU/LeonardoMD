(() => {
  "use strict";

  // Source ranges belong to lexical leaves, never to regenerated HTML. Edits
  // preserve all bytes outside that range (including CRLF and front matter).
  let source = "";
  let ranges = [];
  let enabled = false;
  let renderID = "";
  const escapeHTML = (text) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const escapeMarkdown = (text) => text.replace(/&/g, "&amp;").replace(/([\\`*_[\]{}<>#!|~])/g, "\\$1");

  function begin(payload) {
    source = payload.source || "";
    enabled = payload.allowsEditing === true;
    ranges = [];
    renderID = Array.from(crypto.getRandomValues(new Uint32Array(4))).join("-");
  }

  function annotate(tokens) {
    const normalized = source.replace(/\r\n/g, "\n");
    const body = window.LeonardoEditing.body;
    const offset = normalized.length - body.length;
    if (offset < 0 || normalized.slice(offset) !== body) return tokens;
    const originalOffsets = [];
    for (let index = 0; index < source.length; index += 1) {
      if (source[index] === "\r" && source[index + 1] === "\n") continue;
      originalOffsets.push(index);
    }
    originalOffsets.push(source.length);

    function visit(children, lower, upper) {
      let cursor = lower;
      for (const token of children || []) {
        if (!token.raw) continue;
        const start = normalized.indexOf(token.raw, cursor);
        if (start < cursor || start + token.raw.length > upper) continue;
        const end = start + token.raw.length;
        cursor = end;
        if (token.tokens) {
          visit(token.tokens, start, end);
        } else if (token.items) {
          visit(token.items, start, end);
        } else if (token.type === "table") {
          let cellCursor = start;
          for (const cell of [...token.header, ...token.rows.flat()]) {
            const cellStart = normalized.indexOf(cell.text, cellCursor);
            if (cellStart < cellCursor || cellStart + cell.text.length > end) continue;
            visit(cell.tokens, cellStart, cellStart + cell.text.length);
            cellCursor = cellStart + cell.text.length;
          }
        } else if (["text", "escape", "codespan", "code"].includes(token.type)) {
          let textStart = start;
          let textEnd = end;
          if (token.type === "codespan" || token.type === "code") {
            const searchStart = token.type === "code" ? start + token.raw.indexOf("\n") + 1 : start + (token.raw.match(/^`+/)?.[0].length || 0);
            textStart = normalized.indexOf(token.text, searchStart);
            textEnd = textStart + token.text.length;
            if (textStart < searchStart || textEnd > end) continue;
          }
          // Generated math/diagram output and raw HTML remain immutable in
          // preview. Their source stays available in the raw editor.
          if (token.type === "code" && token.lang === "mermaid") continue;
          token.leonardoEditID = ranges.length;
          ranges.push({ start: originalOffsets[textStart], end: originalOffsets[textEnd], code: ["code", "codespan"].includes(token.type) });
        }
      }
    }
    visit(tokens, offset, normalized.length);
    return tokens;
  }

  function span(token, html) {
    if (token.leonardoEditID === undefined) return html;
    return `<span data-leonardo-render="${renderID}" data-leonardo-edit="${token.leonardoEditID}">${html}</span>`;
  }

  function prepare(root) {
    root.querySelectorAll("[data-leonardo-edit]").forEach((element) => {
      if (element.dataset.leonardoRender !== renderID || element.querySelector(".math-rendered")) return;
      const range = ranges[Number(element.dataset.leonardoEdit)];
      if (!range) return;
      element.contentEditable = enabled ? "plaintext-only" : "false";
      element.spellcheck = false;
      element.addEventListener("input", (event) => {
        if (!enabled || event.isComposing) return;
        applyInput(element, range);
      });
      element.addEventListener("compositionend", () => { if (enabled) applyInput(element, range); });
    });
  }

  function applyInput(element, range) {
    const text = element.innerText.replace(/\r\n/g, "\n");
    const replacement = range.code ? text : escapeMarkdown(text).replace(/\n/g, "  \n");
    const previous = source;
    source = source.slice(0, range.start) + replacement + source.slice(range.end);
    if (source === previous) return;
    const delta = replacement.length - (range.end - range.start);
    const oldEnd = range.end;
    range.end = range.start + replacement.length;
    for (const other of ranges) {
      if (other !== range && other.start >= oldEnd) { other.start += delta; other.end += delta; }
    }
    const handler = window.webkit?.messageHandlers?.leonardoEdit;
    if (handler) handler.postMessage({ expected: previous, replacement: source });
  }

  window.LeonardoEditing = {
    body: "", begin, annotate, span, prepare, escapeHTML,
    setEditable(root, value) {
      enabled = value === true;
      root.querySelectorAll("[data-leonardo-edit]").forEach((element) => {
        element.contentEditable = enabled && element.dataset.leonardoRender === renderID && !element.querySelector(".math-rendered") ? "plaintext-only" : "false";
        if (!enabled && element === document.activeElement) element.blur();
      });
    }
  };
})();
