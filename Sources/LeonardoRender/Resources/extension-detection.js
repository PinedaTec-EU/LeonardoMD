(() => {
  "use strict";
  function hasExtras(tokens) {
    if (Object.keys(tokens?.links || {}).some(label => /^\^[^\]\s]+$/.test(label))) return true;
    for (const token of tokens || []) {
      if (["code", "codespan", "html", "escape"].includes(token.type)) continue;
      const first = token.type === "blockquote" ? token.tokens?.[0] : null;
      const quoteText = first?.type === "paragraph" ? String(first.text || "") : "";
      if (/^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*/i.test(quoteText)) return true;
      if (token.type === "link" && /^\[\^[^\]\s]+\]$/.test(token.raw || "")) return true;
      if (token.type === "text" && !token.tokens && /\[\^[^\]\s]+\]/.test(token.raw || "")) return true;
      const children = [...(token.tokens || []), ...(token.items || []).flatMap(item => item.tokens || []),
        ...(token.header || []).flatMap(cell => cell.tokens || []),
        ...(token.rows || []).flatMap(row => row.flatMap(cell => cell.tokens || []))];
      if (hasExtras(children)) return true;
    }
    return false;
  }
  window.LeonardoExtensionDetection = {
    used(root, splitMath, tokens) {
      const used = new Set();
      const fences = { mermaid: "mermaid", "vega-lite": "vega-lite", bibtex: "citations", "csl-json": "citations" };
      root.querySelectorAll("pre code").forEach(code => {
        for (const [language, feature] of Object.entries(fences)) {
          if (code.classList.contains(`language-${language}`)) used.add(feature);
        }
      });
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        if (!node.parentElement || node.parentElement.closest("pre, code, script, style")) continue;
        const text = node.nodeValue || "";
        if (splitMath(text).some(piece => piece.math !== undefined)) used.add("math");
        if (!node.parentElement.closest("a") && /\[((?:@[A-Za-z0-9][A-Za-z0-9_.:-]*(?:\s*[,;]\s*)?)+)\]/.test(text)) used.add("citations");
      }
      if (hasExtras(tokens)) used.add("markdown-extensions");
      return Array.from(used);
    }
  };
})();
