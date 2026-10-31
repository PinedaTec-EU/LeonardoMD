(() => {
  "use strict";
  window.LeonardoExtensionDetection = {
    used(root, splitMath) {
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
        if (/\[\^[^\]\s]+\]/.test(text)) used.add("markdown-extensions");
      }
      root.querySelectorAll("blockquote").forEach(quote => {
        if (/^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]/i.test(quote.textContent || "")) used.add("markdown-extensions");
      });
      return Array.from(used);
    }
  };
})();
