(() => {
  "use strict";

  // Source ranges belong to lexical leaves, never to regenerated HTML. Edits
  // preserve all bytes outside that range (including CRLF and front matter).
  let source = "";
  let ranges = [];
  let originalSource = "";
  let groups = [];
  let enabled = false;
  let renderID = "";
  const escapeHTML = (text) => text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const escapeMarkdown = (text) => text.replace(/&/g, "&amp;").replace(/([\\`*_[\]{}<>#!|~.+()=\-])/g, "\\$1");

  function begin(payload) {
    source = payload.source || "";
    enabled = payload.allowsEditing === true;
    ranges = [];
    groups = [];
    originalSource = source;
    renderID = Array.from(crypto.getRandomValues(new Uint32Array(4))).join("-");
  }

  function annotate(tokens) {
    const normalized = source.replace(/\r\n/g, "\n");
    // Marked token raws use LF, while the MDLF parser deliberately preserves
    // the document's original CRLF body. Compare on the normalized body but
    // keep offsets mapped back to the untouched source below.
    const body = (window.LeonardoEditing.body || "").replace(/\r\n/g, "\n");
    const offset = normalized.length - body.length;
    if (offset < 0 || normalized.slice(offset) !== body) return tokens;
    const originalOffsets = [];
    for (let index = 0; index < source.length; index += 1) {
      originalOffsets.push(index);
      if (source[index] === "\r" && source[index + 1] === "\n") index += 1;
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
          if (["strong", "em", "del"].includes(token.type) && !hasOpaqueContent(token)) {
            const groupStart = originalOffsets[start], groupEnd = originalOffsets[end];
            const leaves = ranges.filter((range) => range.start >= groupStart && range.end <= groupEnd);
            if (leaves.length) {
              const marker = token.type === "em" ? token.raw[0] : token.raw.slice(0, 2);
              groups.push({ start: groupStart, end: groupEnd, marker, leaves });
            }
          }
        } else if (token.items) {
          visit(token.items, start, end);
        } else if (token.type === "table") {
          const lines = token.raw.split("\n");
          let lineStart = start;
          for (let rowIndex = 0; rowIndex < lines.length; rowIndex += 1) {
            const cells = rowIndex === 0 ? token.header : token.rows[rowIndex - 2];
            const lineEnd = lineStart + lines[rowIndex].length;
            let cellCursor = lineStart;
            for (const cell of cells || []) {
              if (!cell.text) continue;
              const cellStart = normalized.indexOf(cell.text, cellCursor);
              if (cellStart < cellCursor || cellStart + cell.text.length > lineEnd) continue;
              visit(cell.tokens, cellStart, cellStart + cell.text.length);
              cellCursor = cellStart + cell.text.length;
            }
            lineStart = lineEnd + 1;
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
          ranges.push({
            start: originalOffsets[token.type === "code" || token.type === "codespan" ? start : textStart],
            end: originalOffsets[token.type === "code" || token.type === "codespan" ? end : textEnd],
            kind: token.type, language: token.lang || ""
          });
        }
      }
    }
    visit(tokens, offset, normalized.length);
    return tokens;
  }

  function hasOpaqueContent(token) {
    if (token.tokens) return token.tokens.some(hasOpaqueContent);
    if (token.type === "br") return false;
    return !["text", "escape", "codespan"].includes(token.type) || token.leonardoEditID === undefined;
  }

  function span(token, html) {
    if (token.leonardoEditID === undefined) return html;
    return `<span data-leonardo-render="${renderID}" data-leonardo-edit="${token.leonardoEditID}">${html}</span>`;
  }

  function prepare(root) {
    if (ranges.length === 0 && !window.LeonardoEditing.body.trim()) {
      const empty = document.createElement("span");
      empty.className = "preview-empty";
      empty.dataset.leonardoRender = renderID;
      empty.dataset.leonardoEdit = "0";
      root.appendChild(empty);
      const needsSeparator = !window.LeonardoEditing.body && source.length > 0 && !/[\r\n]$/.test(source);
      ranges.push({ start: source.length, end: source.length, kind: "text", language: "",
        leadingSeparator: needsSeparator ? (source.includes("\r\n") ? "\r\n" : "\n") : "" });
    }
    root.querySelectorAll("[data-leonardo-edit]").forEach((element) => {
      if (element.dataset.leonardoRender !== renderID || element.querySelector(".math-rendered, .leonardo-field-value")) return;
      const range = ranges[Number(element.dataset.leonardoEdit)];
      if (!range) return;
      element.contentEditable = enabled ? "plaintext-only" : "false";
      element.spellcheck = false;
      range.originalSource = originalSource.slice(range.start, range.end);
      range.replacement = range.originalSource;
      range.originalText = editableText(element);
      range.currentText = range.originalText;
      element.addEventListener("input", () => {
        if (!enabled) return;
        applyInput(element, range);
      });
      element.addEventListener("compositionend", () => { if (enabled) applyInput(element, range); });
    });
  }

  function serialize(text, range) {
    if (range.kind === "codespan" && !text) return "";
    if (range.kind === "code" || range.kind === "codespan") {
      const longest = (text.match(/`+/g) || []).reduce((maximum, run) => Math.max(maximum, run.length), 0);
      const fence = "`".repeat(Math.max(range.kind === "code" ? 3 : 1, longest + 1));
      if (range.kind === "code") return `${fence}${range.language}\n${text}\n${fence}\n`;
      const pad = text.startsWith("`") || text.endsWith("`") || (text.startsWith(" ") && text.endsWith(" ") && text.trim()) ? " " : "";
      return `${fence}${pad}${text}${pad}${fence}`;
    }
    if (!text) return "";
    return (range.leadingSeparator || "") + escapeMarkdown(text).replace(/\n/g, "  \n");
  }

  function editableText(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.nodeValue || "";
    const children = Array.from(node.childNodes);
    if (children.length === 1 && children[0].nodeName === "BR") return "";
    let text = "", previousBlock = false;
    children.forEach((child, index) => {
      const block = /^(DIV|P)$/.test(child.nodeName);
      if (((block && index > 0) || previousBlock) && !text.endsWith("\n")) text += "\n";
      text += child.nodeName === "BR" ? "\n" : editableText(child);
      previousBlock = block;
    });
    return text;
  }

  function applyInput(element, range) {
    const text = editableText(element).replace(/\r\n/g, "\n");
    range.currentText = text;
    range.replacement = text === range.originalText ? range.originalSource : serialize(text, range);
    const previous = source;
    source = patchedSource();
    if (source === previous) return;
    const handler = window.webkit?.messageHandlers?.leonardoEdit;
    if (handler) handler.postMessage({ expected: previous, replacement: source });
  }

  function patchedSource() {
    // Keep immutable original coordinates. Removing an entire empty formatting
    // group supersedes its leaf patches; typing again restores its delimiters.
    let patches = ranges.filter((range) => range.replacement !== undefined &&
      range.replacement !== originalSource.slice(range.start, range.end));
    for (const group of [...groups].sort((left, right) => (left.end - left.start) - (right.end - right.start))) {
      const children = patches.filter((patch) => patch.start >= group.start && patch.end <= group.end);
      if (!children.length) continue;
      const empty = group.leaves.every((leaf) => typeof leaf.currentText === "string" && !leaf.currentText.trim());
      const inner = patchRange(group.start + group.marker.length, group.end - group.marker.length, children);
      const pieces = /^(\s*)([\s\S]*?)(\s*)$/.exec(inner);
      const replacement = empty ? inner : pieces[1] + group.marker + pieces[2] + group.marker + pieces[3];
      patches = patches.filter((patch) => !children.includes(patch));
      patches.push({ start: group.start, end: group.end, replacement });
    }
    return patchRange(0, originalSource.length, patches);
  }

  function patchRange(start, end, patches) {
    let result = "", cursor = start;
    for (const patch of [...patches].sort((left, right) => left.start - right.start)) {
      if (patch.start < cursor || patch.end > end) continue;
      result += originalSource.slice(cursor, patch.start) + patch.replacement;
      cursor = patch.end;
    }
    return result + originalSource.slice(cursor, end);
  }

  window.LeonardoEditing = {
    body: "", begin, annotate, span, prepare, escapeHTML,
    currentSource: () => source,
    currentBody() {
      // Markdown display bodies may use LF while the authoritative source
      // retains CRLF. Locate the boundary in one coordinate system, then
      // return normalized current prose for the same Marked lexer.
      const original = originalSource.replace(/\r\n/g, "\n");
      const body = window.LeonardoEditing.body.replace(/\r\n/g, "\n");
      const offset = original.length - body.length;
      if (offset < 0 || original.slice(offset) !== body) return "";
      return source.replace(/\r\n/g, "\n").slice(offset);
    },
    setEditable(root, value) {
      enabled = value === true;
      root.querySelectorAll("[data-leonardo-edit]").forEach((element) => {
        element.contentEditable = enabled && element.dataset.leonardoRender === renderID && !element.querySelector(".math-rendered, .leonardo-field-value") ? "plaintext-only" : "false";
        if (!enabled && element === document.activeElement) element.blur();
      });
    }
  };
})();
