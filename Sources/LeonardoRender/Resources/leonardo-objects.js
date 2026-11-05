(() => {
  "use strict";
  const svgNS = "http://www.w3.org/2000/svg", pt = value => `${value}pt`;
  let payload = {}, root, selected, toolbar, logicalNodes = [], legacyImages = [], backgroundTemplate;
  const label = key => payload.formLabels?.[key] || key;
  const post = body => window.webkit?.messageHandlers?.leonardoObject?.postMessage({source: payload.source, ...body});
  function validRubric(value) {
    if (!Array.isArray(value?.strokes) || !value.strokes.length || value.strokes.length > 256) return false;
    let count = 0;
    return value.strokes.every(stroke => {
      if (!stroke || !/^#[0-9a-f]{6}$/i.test(stroke.color) || !["solid", "brush"].includes(stroke.style)
          || !Number.isFinite(stroke.width) || stroke.width < .5 || stroke.width > 24 || !Array.isArray(stroke.points)
          || !stroke.points.length || (count += stroke.points.length) > 20000) return false;
      return stroke.points.every(point => Number.isFinite(point?.x) && point.x >= 0 && point.x <= 600 && Number.isFinite(point?.y) && point.y >= 0 && point.y <= 200);
    });
  }
  function rubric(value) {
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("viewBox", "0 0 600 200"); svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    for (const stroke of validRubric(value) ? value.strokes : []) {
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
    const nodes = logicalNodes;
    legacyImages.forEach(image => image.remove());
    root.querySelectorAll(":scope > .leonardo-page").forEach(page => page.remove());
    const size = pageSize();
    root.classList.add("leonardo-paginated"); root.style.maxWidth = "none"; root.style.padding = "0";
    let page, content;
    function next() {
      page = document.createElement("section"); page.className = "leonardo-page";
      page.style.width = pt(size.width); page.style.height = pt(size.height);
      page.style.padding = size.margins.map(pt).join(" ");
      page.dataset.page = String(root.querySelectorAll(":scope > .leonardo-page").length + 1);
      if (background) { const copy = background.cloneNode(true); copy.style.zIndex = "-10001"; page.append(copy); }
      content = document.createElement("div"); content.className = "leonardo-page-text"; page.append(content); root.append(page);
    }
    const background = backgroundTemplate;
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
    background?.remove();
  }
  function geometry(element, item) {
    Object.assign(element.style, {left: pt(item.x), top: pt(item.y), width: pt(item.width), height: pt(item.height), zIndex: String(item.z)});
    const page = element.parentElement;
    if (page) {
      const right = Math.max(0, item.x + item.width - page.clientWidth * .75);
      const bottom = Math.max(0, item.y + item.height - page.clientHeight * .75);
      element.style.clipPath = `inset(${pt(Math.max(0, -item.y))} ${pt(right)} ${pt(bottom)} ${pt(Math.max(0, -item.x))})`;
    }
  }
  function clear(notify = true) {
    const hadSelection = !!selected;
    selected?.classList.remove("leonardo-object-selected"); selected = null; toolbar?.remove(); toolbar = null;
    payload.selectedGraphicID = null;
    if (notify && hadSelection) post({selection: null});
  }
  function commit(item) { post({object: item}); }
  function select(element, item, notify = true) {
    if (!payload.allowsEditing || payload.allowsFormFilling) return;
    clear(false); window.getSelection()?.removeAllRanges(); selected = element; payload.selectedGraphicID = item.id;
    element.classList.add("leonardo-object-selected");
    toolbar = document.createElement("div"); toolbar.className = "leonardo-object-toolbar"; toolbar.setAttribute("role", "toolbar");
    toolbar.setAttribute("aria-label", label("Object summary"));
    for (const [key, title] of [["x", "X"], ["y", "Y"], ["z", "Z"]]) {
      const value = document.createElement("span");
      value.textContent = `${title} ${Number(item[key].toFixed(1))}${key === "z" ? "" : " pt"}`;
      toolbar.append(value);
    }
    const inspect = document.createElement("button"); inspect.textContent = label("Inspect");
    inspect.onclick = () => post({selection: item.id, inspect: true}); toolbar.append(inspect);
    element.parentElement.append(toolbar);
    positionToolbar(element, item);
    if (notify) post({selection: item.id});
  }
  function positionToolbar(element, item) {
    if (!toolbar) return;
    const page = element.parentElement, rect = page.getBoundingClientRect();
    const bounds = toolbar.getBoundingClientRect(), width = bounds.width * .75, height = bounds.height * .75;
    const minimum = Math.max(4, -rect.left * .75 + 4);
    const maximum = Math.min(page.clientWidth * .75 - width - 4, (window.innerWidth - rect.left) * .75 - width - 8);
    toolbar.style.left = pt(Math.max(minimum, Math.min(item.x, Math.max(minimum, maximum))));
    toolbar.style.top = pt(Math.max(4, Math.min(page.clientHeight * .75 - height - 4, item.y >= height + 4 ? item.y - height - 4 : item.y + item.height + 8)));
  }
  window.addEventListener("resize", () => { if (selected) positionToolbar(selected, selected.leonardoGraphic); });
  // Capture before lexical text editors can stop propagation. Native inspector
  // focus never enters this document, so its controls retain graphic selection.
  document.addEventListener("pointerdown", event => {
    if (!event.target.closest?.(".leonardo-object, .leonardo-object-toolbar")) clear();
  }, true);
  document.addEventListener("selectionchange", () => {
    const selection = window.getSelection();
    if (selected && selection && !selection.isCollapsed && root?.contains(selection.anchorNode)) clear();
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && selected) { event.preventDefault(); clear(); }
  }, true);
  function setSelection(id) {
    if (!id) { clear(false); return; }
    if (selected?.dataset.object === id) return;
    const element = Array.from(root?.querySelectorAll(".leonardo-object") || []).find(node => node.dataset.object === id);
    if (element) select(element, element.leonardoGraphic, false);
  }
  function interactive(element, item) {
    element.leonardoGraphic = item;
    element.tabIndex = payload.allowsEditing && !payload.allowsFormFilling ? 0 : -1; element.setAttribute("role", "button"); element.setAttribute("aria-label", item.label);
    element.addEventListener("click", e => { e.stopPropagation(); select(element, item); });
    element.addEventListener("keydown", e => {
      if (!payload.allowsEditing || payload.allowsFormFilling) return;
      if (e.key === "Enter" || e.key === " ") { e.preventDefault(); select(element, item); }
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(e.key)) {
        e.preventDefault(); const delta = e.shiftKey ? 10 : 1;
        commit({...item, x: item.x + (e.key === "ArrowLeft" ? -delta : e.key === "ArrowRight" ? delta : 0), y: item.y + (e.key === "ArrowUp" ? -delta : e.key === "ArrowDown" ? delta : 0)});
      }
    });
    const handle = document.createElement("button"); handle.className = "leonardo-object-resize"; handle.setAttribute("aria-label", label("Resize")); element.append(handle);
    element.addEventListener("pointerdown", event => {
      if (event.button !== 0 || !payload.allowsEditing || payload.allowsFormFilling) return;
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
      const cancel = () => { changed = {...item}; geometry(element, item); end(); };
      element.addEventListener("pointermove", move); element.addEventListener("pointerup", end, {once:true}); element.addEventListener("pointercancel", cancel, {once:true});
    });
  }
  function apply(nextRoot, nextPayload) {
    clear(false); root = nextRoot; payload = nextPayload;
    root.classList.remove("leonardo-paginated");
    if (!payload.leonardo) return;
    const objects = payload.leonardo.layout?.objects || [];
    if (!objects.length && !root.querySelector('[data-leonardo-page-break="true"]')) return;
    legacyImages = Array.from(root.querySelectorAll("img")).filter(image => image.style.position === "absolute");
    logicalNodes = Array.from(root.childNodes).filter(node => !node.classList?.contains("leonardo-document-background"));
    backgroundTemplate = root.querySelector(":scope > .leonardo-document-background");
    for (const image of root.querySelectorAll("img")) {
      if (!image.closest(".leonardo-document-background")) image.addEventListener("load", refresh);
    }
    paginate();
    renderLegacyImages();
    renderObjects(objects);
    setSelection(payload.selectedGraphicID);
  }
  function renderLegacyImages() {
    const page = root.querySelector(":scope > .leonardo-page");
    if (!page || !legacyImages.length) return;
    const layer = document.createElement("div"); layer.className = "leonardo-legacy-images";
    page.append(layer);
    legacyImages.forEach(image => layer.append(image));
  }
  function renderObjects(objects) {
    for (const item of objects) {
      const page = root.querySelector(`:scope > .leonardo-page[data-page="${item.page}"]`);
      if (!page) continue;
      const element = document.createElement("div"); element.className = "leonardo-object"; element.dataset.object = item.id;
      if (item.rubric) element.append(rubric(item.rubric));
      else { const image = document.createElement("img"); image.alt = item.label; image.loading = "eager"; image.src = item.source; element.append(image); }
      page.append(element); geometry(element, item);
      interactive(element, item);
    }
  }
  function refresh() {
    if (!root?.classList.contains("leonardo-paginated")) return;
    const selectedID = selected?.dataset.object || payload.selectedGraphicID;
    clear(false);
    for (const child of Array.from(root.childNodes)) {
      if (!child.classList?.contains("leonardo-page") && !child.classList?.contains("leonardo-document-background") && !logicalNodes.includes(child)) logicalNodes.push(child);
    }
    paginate(); renderLegacyImages(); renderObjects(payload.leonardo?.layout?.objects || []);
    if (selectedID && payload.allowsEditing && !payload.allowsFormFilling) {
      const element = Array.from(root.querySelectorAll(".leonardo-object")).find(node => node.dataset.object === selectedID);
      if (element) {
        if (root.classList.contains("leonardo-form-export")) payload.selectedGraphicID = selectedID;
        else select(element, element.leonardoGraphic, false);
      }
    }
  }
  function pdfGeometry() {
    if (!root?.classList.contains("leonardo-paginated")) return null;
    return JSON.stringify({documentWidth: document.documentElement.scrollWidth, pages: Array.from(root.querySelectorAll(":scope > .leonardo-page")).map(page => {
      const rect = page.getBoundingClientRect();
      return {x: rect.left + window.scrollX, y: rect.top + window.scrollY, width: rect.width, height: rect.height, overflow: page.dataset.overflow === "true"};
    })});
  }
  window.LeonardoObjects = {apply, rubric, clear, setSelection, refresh, validRubric, pdfGeometry, setEditable(value) {
    payload.allowsEditing = value;
    if (!value) clear();
    root?.querySelectorAll(".leonardo-object").forEach(element => { element.tabIndex = value && !payload.allowsFormFilling ? 0 : -1; });
  }, selectObject(id) {
    if (!payload.allowsEditing || payload.allowsFormFilling) return;
    const element = Array.from(root.querySelectorAll(".leonardo-object")).find(node => node.dataset.object === id);
    if (element) { select(element, element.leonardoGraphic); element.scrollIntoView({block: "nearest"}); element.focus(); }
  }};
})();
