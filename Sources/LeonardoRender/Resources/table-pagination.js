(() => {
  "use strict";

  function tableFor(viewport) {
    if (!viewport.matches?.(".table-viewport")) return null;
    const table = viewport.querySelector(":scope > table");
    if (!table || !window.LeonardoTables.isMarkdownTable(table)) return null;
    return table;
  }

  function cloneHeader(header) {
    const copy = header.cloneNode(true);
    // Continuations repeat labels, not source editing identities or form controls.
    copy.querySelectorAll("[id], [data-leonardo-edit], [contenteditable]").forEach(element => {
      element.removeAttribute("id");
      element.removeAttribute("data-leonardo-edit");
      element.removeAttribute("contenteditable");
    });
    return copy;
  }

  function fragmentState(viewport, table) {
    const body = table.tBodies[0], header = table.tHead;
    if (header?.rows.length !== 1 || table.tBodies.length !== 1 || body.rows.length < 2 ||
        table.querySelector("[rowspan], [colspan]") || header.querySelector(".leonardo-form-field")) return null;

    const rows = Array.from(body.rows);
    const originalStyle = table.getAttribute("style");
    const width = table.getBoundingClientRect().width;
    const originalColumns = table.querySelector(":scope > colgroup");
    const columns = document.createElement("colgroup");
    for (const cell of header.rows[0].cells) {
      const column = document.createElement("col");
      column.style.width = `${cell.getBoundingClientRect().width}px`;
      columns.append(column);
    }

    // A table-wide height distributes minimum space across rows. Keep that space
    // with the original rows instead of applying the full height on every page.
    const heights = table.style.height ? Array.from(table.rows, row => ({
      row, original: row.style.height, measured: row.getBoundingClientRect().height
    })) : [];
    heights.forEach(({row, measured}) => { row.style.height = `${measured}px`; });
    const repeatHeader = header.style.display !== "table-row-group";
    originalColumns?.remove();
    table.prepend(columns);
    table.style.width = `${width}px`;
    table.style.tableLayout = "fixed";
    table.style.height = "";
    viewport.classList.add("table-fragmented");
    rows.forEach(row => row.remove());

    return {
      body, rows,
      continuation() {
        const wrapper = viewport.cloneNode(false);
        const fragment = table.cloneNode(false);
        fragment.removeAttribute("data-leonardo-gfm");
        wrapper.append(fragment);
        fragment.append(columns.cloneNode(true));
        if (repeatHeader) fragment.append(cloneHeader(header));
        const target = fragment.createTBody();
        return {wrapper, target};
      },
      restore() {
        rows.forEach(row => body.append(row));
        heights.forEach(({row, original}) => { row.style.height = original; });
        columns.remove();
        if (originalColumns) table.prepend(originalColumns);
        if (originalStyle === null) table.removeAttribute("style");
        else table.setAttribute("style", originalStyle);
        viewport.classList.remove("table-fragmented");
      }
    };
  }

  function split(viewport, table, page) {
    const state = fragmentState(viewport, table);
    if (!state) return null;

    let body = state.body;
    for (const row of state.rows) {
      body.append(row);
      if (page.fits()) continue;
      if (body === state.body && body.rows.length === 1) {
        page.moveTable(viewport);
      } else if (body.rows.length > 1) {
        page.next();
        const {wrapper, target} = state.continuation();
        page.append(wrapper);
        body = target;
        body.append(row);
      }
      if (!page.fits()) page.markOverflow();
    }
    return state.restore;
  }

  window.LeonardoTablePagination = {tableFor, split};
})();
