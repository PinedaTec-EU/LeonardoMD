(() => {
  "use strict";

  let enabled = false;
  const delimiters = [
    { left: "$$", right: "$$", display: true },
    { left: "\\[", right: "\\]", display: true },
    { left: "\\(", right: "\\)", display: false },
    { left: "$", right: "$", display: false }
  ];

  function matchMath(source) {
    if (!enabled) return;
    const delimiter = delimiters.find(({ left }) => source.startsWith(left));
    if (!delimiter) return;
    let depth = 0;
    for (let index = delimiter.left.length; index < source.length; index += 1) {
      if (delimiter.left === "$" && source[index] === "\n") return;
      if (depth === 0 && source.startsWith(delimiter.right, index)) {
        const text = source.slice(delimiter.left.length, index);
        if (!text.trim()) return;
        return { raw: source.slice(0, index + delimiter.right.length), text, display: delimiter.display };
      }
      if (source[index] === "\\") index += 1;
      else if (source[index] === "{") depth += 1;
      else if (source[index] === "}") depth = Math.max(0, depth - 1);
    }
  }

  function render(token) {
    // TeX is text until the runtime invokes KaTeX with trust disabled. No
    // Markdown leaves/edit ranges are generated inside this opaque token.
    return `<span class="math-source" data-math-display="${token.display}">${window.LeonardoEditing.escapeHTML(token.text)}</span>`;
  }

  window.LeonardoMath = {
    setEnabled(value) { enabled = value === true; },
    extensions: [
      {
        name: "leonardoMathBlock", level: "block",
        start(source) { return enabled ? source.search(/^(?: {0,3})(?:\$\$|\\\[)/m) : -1; },
        tokenizer(source) {
          const prefix = /^( {0,3})(?=\$\$|\\\[)/.exec(source);
          if (!prefix) return;
          const token = matchMath(source.slice(prefix[0].length));
          if (!token) return;
          const rest = source.slice(prefix[0].length + token.raw.length);
          const end = /^[ \t]*(?:\n|$)/.exec(rest);
          if (!end) return; // Inline display math can have surrounding prose.
          return { ...token, type: "leonardoMathBlock", raw: prefix[0] + token.raw + end[0] };
        },
        renderer: render
      },
      {
        name: "leonardoMathInline", level: "inline",
        start(source) { return enabled ? source.search(/\$|\\[[(]/) : -1; },
        tokenizer(source) {
          if (this.lexer.state.inRawBlock) return;
          const token = matchMath(source);
          if (token) return { ...token, type: "leonardoMathInline" };
        },
        renderer: render
      }
    ]
  };
})();
