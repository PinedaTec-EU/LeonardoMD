(() => {
  "use strict";
  const svgNS = "http://www.w3.org/2000/svg", pt = value => `${value}pt`;
  let payload = {}, root, selected, toolbar;
  const label = key => payload.formLabels?.[key] || key;
  const post = body => window.webkit?.messageHandlers?.leonardoObject?.postMessage({source: payload.source, ...body});
  function rubric(value) {
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 600 200"); svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    for (const stroke of value?.strokes || []) {
      const points = stroke.points || [];
      points.forEach((point, index) => {
        const width = stroke.width * (stroke.style === "brush" ? Math.max(.08, Math.sin(Math.PI * index / Math.max(1, points.length - 1))) : 1);
        const previous = points[Math.max(0, index - 1)], line = document.createElementNS(svgNS, "line");
        for (const [key, val] of Object.entries({x1: previous.x, y1: previous.y, x2: point.x, y2: point.y, stroke: stroke.color, "stroke-width": width, "stroke-linecap": "round"})) line.setAttribute(key, String(val));
        svg.append(line);
      });
    }
    return svg;
  }
  function pageSize() {
    const page = payload.leonardo?.layout?.page || {}, margins = page.margins || {};
    let [width, height] = page.size === "letter" ? [612, 792] : page.size === "custom" ? [page.widthPoints, page.heightPoints] : [595.276, 841.89];
    if (page.orientation === "landscape") [width, height] = [height, width];
    return {width, height, margins: ["top", "right", "bottom", "left"].map(side => margins[side] ?? 36)};
  }
  function paginate() {
    const nodes = Array.from(root.childNodes).filter(node => !node.classList?.contains("leonardo-document-background"));
    const size = pageSize();
    root.classList.add("leonardo-paginated"); root.style.maxWidth = "none"; root.style.padding = "0";
    let page, content;
    function next() {
      page = document.createElement("section"); page.className = "leonardo-page";
      page.style.width = pt(size.width); page.style.height = pt(size.height);
      page.style.padding = size.margins.map(pt).join(" ");
      page.dataset.page = String(root.querySelectorAll(":scope > .leonardo-page").length + 1);
      content = document.createElement("div"); content.className = "leonardo-page-text"; page.append(content); root.append(page);
    }
    next();
    for (const node of nodes) {
      if (node.nodeType === Node.TEXT_NODE && !node.textContent.trim()) { node.remove(); continue; }
      if (node.matches?.('[data-leonardo-page-break="true"]')) { node.remove(); next(); continue; }
      content.append(node);
      const available = (size.height - size.margins[0] - size.margins[2]) * 4 / 3;
      if (content.getBoundingClientRect().height > available + 1 && content.childNodes.length > 1) {
        next(); content.append(node);
      }
      if (content.getBoundingClientRect().height > available + 1) {
        page.dataset.overflow = "true";
        page.title = label("Content exceeds page height. Split the block before exporting.");
      }
    }
    const last = Math.max(1, ...(payload.leonardo?.layout?.objects || []).map(item => item.page));
    while (root.querySelectorAll(":scope > .leonardo-page").length < last) next();
  }
  function geometry(element, item) {
    Object.assign(element.style, {left: pt(item.x), top: pt(item.y), width: pt(item.width), height: pt(item.height), zIndex: String(item.z)});
  }
  function clear() { selected?.classList.remove("leonardo-object-selected"); selected = null; toolbar?.remove(); toolbar = null; }
  function commit(item) { post({object: item}); }
  function select(element, item) {
    clear(); selected = element; element.classList.add("leonardo-object-selected");
    toolbar = document.createElement("div"); toolbar.className = "leonardo-object-toolbar"; toolbar.setAttribute("role", "toolbar");
    toolbar.setAttribute("aria-label", label("Position and size"));
    for (const [key, title] of [["page", "Page"], ["x", "X"], ["y", "Y"], ["width", "Width"], ["height", "Height"], ["z", "Z"]]) {
      const caption = document.createElement("label"); caption.textContent = label(title);
      const input = document.createElement("input"); input.type = "number"; input.value = item[key]; input.setAttribute("aria-label", label(title));
      input.step = ["page", "z"].includes(key) ? "1" : "0.5";
      input.addEventListener("change", () => {
        const value = Number(input.value); if (!Number.isFinite(value)) return;
        const changed = {...item, [key]: value};
        if (key === "width" && value > 0) changed.height = item.height * value / item.width;
        if (key === "height" && value > 0) changed.width = item.width * value / item.height;
        commit(changed);
      });
      caption.append(input); toolbar.append(caption);
    }
    for (const [title, action] of [["Bring forward", () => commit({...item, z: Math.min(10000, item.z + 1)})], ["Send backward", () => commit({...item, z: Math.max(-10000, item.z - 1)})], ["Delete", () => post({remove: item.id})]]) {
      const button = document.createElement("button"); button.textContent = label(title); button.onclick = action; toolbar.append(button);
    }
    element.parentElement.append(toolbar);
    toolbar.style.left = "8pt"; toolbar.style.top = pt(Math.max(4, item.y - 48));
  }
  function interactive(element, item) {
    element.tabIndex = 0; element.setAttribute("role", "button"); element.setAttribute("aria-label", item.label);
    element.addEventListener("click", e => { e.stopPropagation(); select(element, item); });
    element.addEventListener("keydown", e => {
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); select(element, item); }
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) {
        e.preventDefault(); const delta = e.shiftKey ? 10 : 1;
        commit({...item, x: item.x + (e.key === "ArrowLeft" ? -delta : e.key === "ArrowRight" ? delta : 0), y: item.y + (e.key === "ArrowUp" ? -delta : e.key === "ArrowDown" ? delta : 0)});
      }
    });
    const handle = document.createElement("button"); handle.className = "leonardo-object-resize"; handle.setAttribute("aria-label", label("Resize")); element.append(handle);
    element.addEventListener("pointerdown", event => {
      if (event.button !== 0) return;
      event.preventDefault(); event.stopPropagation(); select(element, item);
      const resize = event.target === handle, start = {x: event.clientX, y: event.clientY};
      let changed = {...item}; element.setPointerCapture(event.pointerId);
      const move = e => {
        const dx = (e.clientX - start.x) * .75, dy = (e.clientY - start.y) * .75;
        changed = resize ? {...item, width: Math.max(4, item.width + dx), height: Math.max(4, item.width + dx) * item.height / item.width} : {...item, x: item.x + dx, y: item.y + dy};
        geometry(element, changed);
      };
      const end = () => {
        element.removeEventListener("pointermove", move); element.removeEventListener("pointerup", end); element.removeEventListener("pointercancel", cancel);
        if (JSON.stringify(changed) !== JSON.stringify(item)) commit(changed);
      };
      const cancel = () => { geometry(element, item); end(); };
      element.addEventListener("pointermove", move); element.addEventListener("pointerup", end, {once:true}); element.addEventListener("pointercancel", cancel, {once:true});
    });
  }
  function apply(nextRoot, nextPayload) {
    clear(); root = nextRoot; payload = nextPayload;
    root.classList.remove("leonardo-paginated");
    if (!payload.leonardo) return;
    const objects = payload.leonardo.layout?.objects || [];
    if (!objects.length && !root.querySelector('[data-leonardo-page-break="true"]')) return;
    paginate();
    for (const item of objects) {
      const page = root.querySelector(`:scope > .leonardo-page[data-page="${item.page}"]`);
      if (!page) continue;
      const element = document.createElement("div"); element.className = "leonardo-object"; element.dataset.object = item.id;
      if (item.rubric) element.append(rubric(item.rubric));
      else { const image = document.createElement("img"); image.alt = item.label; image.loading = "eager"; image.src = item.source; element.append(image); }
      geometry(element, item); page.append(element);
      if (payload.allowsEditing && !payload.allowsFormFilling) interactive(element, item);
    }
  }
  window.LeonardoObjects = {apply, rubric, clear};
})();
