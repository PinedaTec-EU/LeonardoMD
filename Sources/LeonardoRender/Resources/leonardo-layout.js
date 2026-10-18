(() => {
  "use strict";
  const anchors = {
    topLeading: ["left top", "0%", "0%"], top: ["center top", "-50%", "0%"],
    topTrailing: ["right top", "-100%", "0%"], leading: ["left center", "0%", "-50%"],
    center: ["center center", "-50%", "-50%"], trailing: ["right center", "-100%", "-50%"],
    bottomLeading: ["left bottom", "0%", "-100%"], bottom: ["center bottom", "-50%", "-100%"],
    bottomTrailing: ["right bottom", "-100%", "-100%"]
  };
  function dimension(value) {
    if (!value || !Number.isFinite(value.value) || Math.abs(value.value) > 100000) return null;
    if (value.unit === "percent") return `${value.value}%`;
    if (value.unit === "points") return `${value.value}pt`;
    return null;
  }
  function position(element, value) {
    if (!value || !["relative", "absolute"].includes(value.placement)) return;
    element.style.position = value.placement;
    element.style.left = dimension(value.x) || "0";
    element.style.top = dimension(value.y) || "0";
    const anchor = anchors[value.anchor] || anchors.topLeading;
    element.style.transform = `translate(${anchor[1]}, ${anchor[2]})`;
  }
  function fillText(root, metadata) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (!node.parentElement?.closest("code, pre, script, style")) nodes.push(node);
    }
    for (const node of nodes) {
      const expression = /\{\{\s*field:([A-Za-z][A-Za-z0-9_.-]{0,63})\s*\}\}/g;
      const text = node.nodeValue || "";
      let cursor = 0, match;
      const fragment = document.createDocumentFragment();
      while ((match = expression.exec(text))) {
        const field = metadata.fields?.[match[1]];
        if (!field) continue;
        fragment.append(document.createTextNode(text.slice(cursor, match.index)));
        const span = document.createElement("span");
        span.className = "leonardo-field-value";
        span.dataset.field = match[1];
        span.setAttribute("aria-label", field.label || match[1]);
        const value = Object.hasOwn(metadata.values || {}, match[1]) ? metadata.values[match[1]] : field.defaultValue;
        span.textContent = value === null || value === undefined ? "________" : String(value);
        fragment.append(span);
        cursor = match.index + match[0].length;
      }
      if (cursor) {
        fragment.append(document.createTextNode(text.slice(cursor)));
        node.replaceWith(fragment);
      }
    }
  }
  function applyImages(root, images) {
    for (const descriptor of images || []) {
      const image = Array.from(root.querySelectorAll("img")).filter(node => node.getAttribute("src") === descriptor.source)[(descriptor.occurrence || 1) - 1];
      if (!image) continue;
      image.style.width = dimension(descriptor.size?.width) || "";
      image.style.height = dimension(descriptor.size?.height) || "";
      image.style.maxWidth = "none";
      if (descriptor.size?.preserveAspectRatio !== false) {
        if (!descriptor.size?.height) image.style.height = "auto";
        if (!descriptor.size?.width) image.style.width = "auto";
      }
      if (["contain", "cover", "fill", "none"].includes(descriptor.fit)) image.style.objectFit = descriptor.fit;
      if (Number.isFinite(descriptor.opacity)) image.style.opacity = String(Math.min(1, Math.max(0, descriptor.opacity)));
      position(image, descriptor.position);
    }
  }
  function applyTables(root, tables) {
    const nodes = root.querySelectorAll("table");
    for (const descriptor of tables || []) {
      const table = nodes[(descriptor.occurrence || 1) - 1];
      if (!table) continue;
      table.querySelector("colgroup")?.remove();
      table.removeAttribute("style");
      table.classList.remove("table-sized");
      const group = document.createElement("colgroup");
      table.style.tableLayout = "fixed";
      table.style.width = dimension(descriptor.width) || "100%";
      for (const column of descriptor.columns || []) {
        const col = document.createElement("col");
        col.style.width = dimension(column.width) || "";
        group.append(col);
      }
      table.prepend(group);
      table.querySelectorAll("tr").forEach(row => {
        row.style.breakInside = descriptor.allowRowBreak === false ? "avoid" : "auto";
        Array.from(row.children).forEach((cell, index) => {
          const column = descriptor.columns?.[index];
          cell.style.minWidth = dimension(column?.minimumWidth) || "";
          cell.style.maxWidth = dimension(column?.maximumWidth) || "";
        });
      });
      const header = table.querySelector("thead");
      if (header) header.style.display = descriptor.repeatHeader === false ? "table-row-group" : "table-header-group";
    }
  }
  function applyPage(root, page) {
    document.getElementById("leonardo-page-style")?.remove();
    if (!page) return;
    const presets = { a4: [595.276, 841.89], letter: [612, 792] };
    let [width, height] = presets[page.size] || [page.widthPoints, page.heightPoints];
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    if (page.orientation === "landscape") [width, height] = [height, width];
    root.style.boxSizing = "border-box";
    root.style.maxWidth = `${width}pt`;
    root.style.minHeight = `${height}pt`;
    const margins = page.margins || {};
    const spacing = ["top", "right", "bottom", "left"].map(side => {
      const value = margins[side];
      return `${Number.isFinite(value) && value >= 0 ? Math.min(value, 10000) : 36}pt`;
    }).join(" ");
    root.style.padding = spacing;
    const style = document.createElement("style");
    style.id = "leonardo-page-style";
    style.textContent = `@page { size: ${width}pt ${height}pt; margin: ${spacing}; } @media print { #leonardo-markdown { padding: 0; min-height: 0; max-width: none; } }`;
    document.head.append(style);
  }
  function applyBackground(root, background) {
    root.querySelector(":scope > .leonardo-document-background")?.remove();
    if (!background) return;
    if (background.color && /^#[0-9a-f]{3,8}$/i.test(background.color)) root.style.backgroundColor = background.color;
    if (!background.image) return;
    // Use an img so the existing asset containment/CSP and PDF readiness checks apply.
    const layer = document.createElement("div");
    layer.className = "leonardo-document-background";
    layer.setAttribute("aria-hidden", "true");
    const image = document.createElement("img");
    image.alt = "";
    image.src = background.image;
    image.style.width = "100%";
    image.style.height = "100%";
    image.style.objectFit = ["contain", "cover", "fill", "none"].includes(background.fit) ? background.fit : "cover";
    image.style.objectPosition = (anchors[background.position?.anchor] || anchors.center)[0];
    const x = dimension(background.position?.x), y = dimension(background.position?.y);
    if (x || y) image.style.objectPosition = `${x || "50%"} ${y || "50%"}`;
    layer.style.opacity = Number.isFinite(background.opacity) ? String(Math.min(1, Math.max(0, background.opacity))) : "1";
    layer.append(image);
    root.prepend(layer);
  }
  window.LeonardoLayout = {
    apply(root, payload) {
      root.classList.toggle("leonardo-document", !!payload.leonardo);
      root.style.maxWidth = ""; root.style.minHeight = ""; root.style.padding = ""; root.style.backgroundColor = "";
      document.getElementById("leonardo-page-style")?.remove();
      if (!payload.leonardo) return;
      const metadata = payload.leonardo;
      fillText(root, metadata);
      const layout = metadata.layout || {};
      applyImages(root, layout.images);
      applyTables(root, layout.tables);
      applyPage(root, layout.page);
      applyBackground(root, layout.background);
    }
  };
})();
