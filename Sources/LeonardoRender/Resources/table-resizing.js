(() => {
  "use strict";
  const pointsPerPixel = 72 / 96;
  const maximumPixels = 10000 / pointsPerPixel;
  const minimumColumn = 36, minimumRow = 24;
  let enabled = false, active = null, observers = [], payload = null;

  function geometry(table) {
    return {
      widths: Array.from(table.rows[0]?.cells || [], cell => cell.getBoundingClientRect().width),
      heights: Array.from(table.rows, row => row.getBoundingClientRect().height)
    };
  }
  function restore(drag) {
    drag.table.setAttribute("style", drag.style);
    drag.table.className = drag.className;
    drag.table.querySelector("colgroup")?.remove();
    if (drag.columns) drag.table.prepend(drag.columns);
    Array.from(drag.table.rows).forEach((row, i) => row.setAttribute("style", drag.rows[i]));
  }
  function cancel() {
    if (!active) return;
    const drag = active; active = null;
    restore(drag);
  }
  function apply(table, widths, heights) {
    let group = table.querySelector("colgroup");
    if (!group) { group = document.createElement("colgroup"); table.prepend(group); }
    group.replaceChildren(...widths.map(width => {
      const col = document.createElement("col"); col.style.width = `${width}px`; return col;
    }));
    table.classList.add("table-sized");
    table.style.tableLayout = "fixed";
    table.style.width = `${widths.reduce((sum, width) => sum + width, 0)}px`;
    table.style.height = `${heights.reduce((sum, height) => sum + height, 0)}px`;
    Array.from(table.rows).forEach((row, i) => { row.style.height = `${heights[i]}px`; });
  }
  function boundColumns(widths, descriptor) {
    const total = widths.reduce((a, b) => a + b, 0);
    return widths.map((width, index) => {
      const column = descriptor?.columns?.[index];
      const pixels = value => value?.unit === "percent" ? total * value.value / 100 : value?.value / pointsPerPixel;
      const minimum = Math.max(minimumColumn, pixels(column?.minimumWidth) || 0);
      const maximum = Math.max(minimum, pixels(column?.maximumWidth) || maximumPixels);
      return Math.min(maximum, Math.max(minimum, width));
    });
  }
  function move(event) {
    const drag = active;
    if (!drag || drag.pointer !== event.pointerId) return;
    const dx = event.clientX - drag.x, dy = event.clientY - drag.y;
    // A click or tiny pointer tremor does not materialize fixed dimensions.
    if (!drag.moved && Math.max(Math.abs(dx), Math.abs(dy)) < 3) return;
    drag.moved = true;
    let widths = [...drag.initial.widths], heights = [...drag.initial.heights];
    if (drag.kind === "column") widths[drag.index] = Math.max(minimumColumn, widths[drag.index] + dx);
    if (drag.kind === "row") heights[drag.index] = Math.max(minimumRow, heights[drag.index] + dy);
    if (["width", "both"].includes(drag.kind)) {
      const total = widths.reduce((a, b) => a + b, 0);
      const ratio = Math.min(maximumPixels, Math.max(minimumColumn * widths.length, total + dx)) / total;
      widths = widths.map(width => Math.max(minimumColumn, width * ratio));
    }
    if (["height", "both"].includes(drag.kind)) {
      const total = heights.reduce((a, b) => a + b, 0);
      const ratio = Math.min(maximumPixels, Math.max(minimumRow * heights.length, total + dy)) / total;
      heights = heights.map(height => Math.max(minimumRow, height * ratio));
    }
    widths = boundColumns(widths, drag.descriptor);
    if (widths.reduce((a, b) => a + b, 0) > maximumPixels || heights.reduce((a, b) => a + b, 0) > maximumPixels) return;
    apply(drag.table, widths, heights);
    drag.position();
    event.preventDefault();
  }
  function finish(event) {
    const drag = active;
    if (!drag || drag.pointer !== event.pointerId) return;
    active = null;
    const next = geometry(drag.table);
    const changed = drag.moved && [...next.widths, ...next.heights].some((v, i) => Math.abs(v - [...drag.initial.widths, ...drag.initial.heights][i]) > 0.5);
    if (!changed || !enabled) { restore(drag); return; }
    const handler = window.webkit?.messageHandlers?.leonardoTableResize;
    if (!handler) { restore(drag); return; }
    handler.postMessage({ expected: window.LeonardoEditing.currentSource(), resize: {
      occurrence: drag.occurrence, source: drag.source,
      widths: next.widths.map(v => v * pointsPerPixel), heights: next.heights.map(v => v * pointsPerPixel)
    }});
  }
  function start(event, state, kind, index) {
    if (!enabled || event.button !== 0 || active) return;
    // Blur commits any composed inline text before taking the source snapshot.
    document.activeElement?.blur();
    const table = state.table;
    const occurrence = state.occurrence;
    const source = window.LeonardoTables.sources(window.LeonardoEditing.currentBody())[occurrence - 1];
    if (!source) return;
    const descriptor = payload.leonardo?.layout?.tables?.find(t => t.occurrence === occurrence && (!t.source || t.source === source));
    active = { ...state, kind, index, source, descriptor, pointer: event.pointerId, x: event.clientX, y: event.clientY,
      initial: geometry(table), style: table.getAttribute("style") || "", className: table.className,
      columns: table.querySelector("colgroup")?.cloneNode(true), rows: Array.from(table.rows, row => row.getAttribute("style") || ""), moved: false };
    try { event.currentTarget.setPointerCapture(event.pointerId); } catch (_) { /* Synthetic native test events have no captured pointer. */ }
    event.preventDefault(); event.stopPropagation();
  }
  function prepareTable(table, occurrence) {
    if (!table.rows.length || !table.rows[0].cells.length || table.querySelector("[colspan], [rowspan]")) return;
    const viewport = table.parentElement;
    const overlay = document.createElement("div"); overlay.className = "table-resize-overlay";
    const handles = [];
    const state = { table, occurrence, position };
    function handle(kind, index, label) {
      const node = document.createElement("button"); node.type = "button";
      node.className = `table-resize-handle table-resize-${kind}`;
      node.dataset.resizeKind = kind; node.dataset.resizeIndex = index;
      node.title = (payload.formLabels?.[label] || label) + (index >= 0 ? ` ${index + 1}` : "");
      node.setAttribute("aria-label", node.title);
      node.addEventListener("pointerdown", event => start(event, state, kind, index));
      node.addEventListener("keydown", event => { if (event.key === "Escape") cancel(); });
      overlay.append(node); handles.push({ node, kind, index });
    }
    Array.from(table.rows[0].cells).forEach((_, i) => handle("column", i, "Resize column"));
    Array.from(table.rows).forEach((_, i) => handle("row", i, "Resize row"));
    handle("width", -1, "Resize table width"); handle("height", -1, "Resize table height"); handle("both", -1, "Resize table");
    function position() {
      const rect = table.getBoundingClientRect(), parent = viewport.getBoundingClientRect();
      const left = rect.left - parent.left + viewport.scrollLeft;
      const top = rect.top - parent.top + viewport.scrollTop;
      const headerHeight = table.rows[0].getBoundingClientRect().height;
      for (const {node, kind, index} of handles) {
        let x = left, y = top, width = rect.width, height = 8;
        if (kind === "column") {
          x += table.rows[0].cells[index].getBoundingClientRect().right - rect.left - 4;
          width = 8; height = headerHeight;
        } else if (kind === "row") {
          y += table.rows[index].getBoundingClientRect().bottom - rect.top - 4;
          width = index === table.rows.length - 1 ? 44 : Math.max(44, rect.width - 14);
        } else if (kind === "width") {
          x += rect.width - 4; y += headerHeight; width = 8; height = Math.max(0, rect.height - headerHeight - 8);
        } else if (kind === "height") {
          x += 48; y += rect.height - 4; width = Math.max(0, rect.width - 60);
        } else { x += rect.width - 8; y += rect.height - 8; width = height = 16; }
        Object.assign(node.style, { left: `${x}px`, top: `${y}px`, width: `${width}px`, height: `${height}px` });
        node.disabled = !enabled;
      }
    }
    viewport.append(overlay);
    const observer = new ResizeObserver(position); observer.observe(table); observers.push(observer);
    position();
  }
  document.addEventListener("pointermove", move);
  document.addEventListener("pointerup", finish);
  document.addEventListener("pointercancel", cancel);
  document.addEventListener("keydown", event => { if (event.key === "Escape") cancel(); });
  window.addEventListener("blur", cancel);
  window.LeonardoTableResizing = {
    cancel,
    prepare(root, nextPayload) {
      cancel(); observers.forEach(o => o.disconnect()); observers = [];
      payload = nextPayload; enabled = payload.allowsEditing === true && !payload.allowsFormFilling;
      root.querySelectorAll("table").forEach((table, index) => prepareTable(table, index + 1));
      root.classList.toggle("tables-resizable", enabled);
    },
    setEditable(value) {
      enabled = value === true && !payload?.allowsFormFilling;
      if (!enabled) cancel();
      document.querySelector("main")?.classList.toggle("tables-resizable", enabled);
      document.querySelectorAll(".table-resize-handle").forEach(node => { node.disabled = !enabled; });
    }
  };
})();
