(() => {
  "use strict";

  // Only validated numeric ch values reach CSS; directives never inject markup.
  const directive = /^<!--\s*leonardo:table\s+widths="([^"]+)"\s*-->\s*$/;
  let allowsLegacyWidths = true;
  let tableRenderKey = "";
  const maximumCharacters = 200;
  const automaticMinimumCharacters = 12;
  const horizontalCellPadding = 1.5;

  function parseWidths(raw) {
    const match = directive.exec(raw);
    if (!match) return null;
    const widths = match[1].trim().split(/\s+/);
    return widths.every((width) => width === "auto" || (
      /^[1-9]\d*ch$/.test(width) && Number(width.slice(0, -2)) <= maximumCharacters
    )) ? widths : null;
  }

  function annotateTables(tokens) {
    let pending = null;
    tokens.forEach((token) => {
      if (token.type === "space") return;
      if (token.type === "table" && pending?.length === token.header.length) {
        token.leonardoWidths = pending;
      }
      pending = token.type === "html" ? parseWidths(token.raw) : null;
      if (token.tokens) annotateTables(token.tokens);
      if (token.items) token.items.forEach((item) => annotateTables(item.tokens));
    });
    return tokens;
  }

  function sizedTable(token) {
    const widths = token.leonardoWidths;
    const html = window.marked.Renderer.prototype.table.call(this, token);
    const opening = `<table data-leonardo-gfm="${tableRenderKey}"`;
    if (!widths) return html.replace("<table>", `${opening}>`);
    const characters = widths.reduce((sum, width) => sum + (
      width === "auto" ? automaticMinimumCharacters : Number(width.slice(0, -2))
    ), 0);
    const padding = widths.length * horizontalCellPadding;
    const total = `calc(${characters}ch + ${padding}em + ${widths.length + 1}px)`;
    const tableWidth = widths.includes("auto") ? `max(100%, ${total})` : total;
    const columns = widths.map((width) => width === "auto" ? "<col>" :
      `<col style="width: calc(${width} + ${horizontalCellPadding}em + 1px)">`).join("");
    return html.replace("<table>",
      `${opening} class="table-sized" style="width: ${tableWidth}"><colgroup>${columns}</colgroup>`);
  }

  const parser = new window.marked.Marked({
    gfm: true,
    extensions: window.LeonardoMath?.extensions || [],
    breaks: false,
    hooks: { processAllTokens: (tokens) => window.LeonardoEditing.annotate(allowsLegacyWidths ? annotateTables(tokens) : tokens) },
    renderer: {
      table: sizedTable,
      text(token) {
        const html = window.marked.Renderer.prototype.text.call(this, token);
        return window.LeonardoEditing.span(token, html);
      },
      codespan(token) {
        return `<code>${window.LeonardoEditing.span(token, window.LeonardoEditing.escapeHTML(token.text))}</code>`;
      },
      code(token) {
        const html = window.marked.Renderer.prototype.code.call(this, token);
        if (token.leonardoEditID === undefined) return html;
        return html.replace(/(<code[^>]*>)([\s\S]*)(<\/code>)/, (_, open, body, close) =>
          open + window.LeonardoEditing.span(token, body.replace(/\n$/, "")) + close);
      }
    }
  });

  window.LeonardoTables = {
    render(markdown, legacyWidths = true) {
      allowsLegacyWidths = legacyWidths;
      tableRenderKey = Array.from(crypto.getRandomValues(new Uint32Array(4))).join("-");
      return parser.parse(markdown);
    },
    isMarkdownTable: table => table.dataset.leonardoGfm === tableRenderKey,
    sourceFor(table, root, markdown) {
      const nodes = Array.from(root.querySelectorAll("table")).filter(this.isMarkdownTable);
      return this.sources(markdown)[nodes.indexOf(table)];
    },
    sources(markdown) {
      const tables = [];
      function visit(tokens) {
        for (const token of tokens || []) {
          if (token.type === "table") tables.push(token.raw);
          else if (token.tokens) visit(token.tokens);
          if (token.items) token.items.forEach(item => visit(item.tokens));
        }
      }
      visit(parser.lexer(markdown));
      return tables;
    },
    prepare(root) {
      root.querySelectorAll("table").forEach((table) => {
        const viewport = document.createElement("div");
        viewport.className = "table-viewport";
        // Keyboard users can reach and scroll an overflowing table.
        viewport.tabIndex = 0;
        table.before(viewport);
        viewport.appendChild(table);
      });
    }
  };
})();
