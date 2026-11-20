(() => {
  "use strict";

  let payload, root, fields = [], selected;
  const pointsPerPixel = 0.75;
  const label = key => payload.formLabels?.[key] || key;
  const editable = () => payload?.allowsEditing && !payload.allowsFormFilling;

  function select(entry) {
    selected?.wrapper.classList.remove("leonardo-object-selected");
    selected = entry;
    selected?.wrapper.classList.add("leonardo-object-selected");
  }

  document.addEventListener("pointerdown", event => {
    if (!selected?.wrapper.contains(event.target)) select(null);
  }, true);
  document.addEventListener("keydown", event => {
    if (event.key === "Escape" && selected) select(null);
  });

  function sizeField(entry, size) {
    for (const control of entry.wrapper.querySelectorAll(".leonardo-rubric-field")) {
      control.style.width = `${size.width}pt`;
      control.style.height = `${size.height}pt`;
    }
    if (entry.placement) entry.wrapper.style.transformOrigin = `${size.width / 2}pt ${size.height / 2}pt`;
  }

  function commit(entry, placement, size) {
    window.webkit?.messageHandlers?.leonardoObject?.postMessage({
      source: payload.source, rubricLayout: {fieldID: entry.fieldID, placement, size}
    });
  }

  function origin(entry, page) {
    const {wrapper, placement} = entry;
    if (placement) return placement;
    const bounds = wrapper.getBoundingClientRect(), frame = page.getBoundingClientRect();
    return {
      page: Number(page.dataset.page),
      x: (bounds.left - frame.left) * pointsPerPixel,
      y: (bounds.top - frame.top) * pointsPerPixel,
      rotation: 0
    };
  }

  function beginGesture(event, entry) {
    if (!editable() || event.button !== 0 || event.target === entry.rotate) return;
    const {wrapper, size, placement} = entry;
    const page = wrapper.closest(".leonardo-page");
    if (!page) return;
    event.preventDefault();
    event.stopPropagation();
    select(entry);
    const resizing = event.target === entry.handle;
    const start = origin(entry, page);
    const startX = event.clientX, startY = event.clientY;
    const angle = start.rotation * Math.PI / 180;
    let nextSize = size, nextPlacement = placement;
    wrapper.setPointerCapture(event.pointerId);

    function move(current) {
      const dx = (current.clientX - startX) * pointsPerPixel;
      const dy = (current.clientY - startY) * pointsPerPixel;
      if (resizing) {
        const localX = dx * Math.cos(angle) + dy * Math.sin(angle);
        const width = Math.min(10000, 10000 * size.width / size.height,
          Math.max(Math.min(12, size.width), size.width + localX));
        nextSize = {width, height: width * size.height / size.width};
        sizeField(entry, nextSize);
      } else if (nextPlacement !== placement || Math.hypot(dx, dy) >= 2) {
        nextPlacement = {...start, x: start.x + dx, y: start.y + dy};
        wrapper.style.translate = `${dx}pt ${dy}pt`;
      }
    }

    function end(current) {
      wrapper.removeEventListener("pointermove", move);
      wrapper.removeEventListener("pointerup", end);
      wrapper.removeEventListener("pointercancel", end);
      wrapper.style.translate = "";
      sizeField(entry, size);
      if (current.type === "pointerup" && editable() &&
          (nextSize.width !== size.width || nextPlacement !== placement)) {
        commit(entry, nextPlacement, nextSize);
      }
    }

    wrapper.addEventListener("pointermove", move);
    wrapper.addEventListener("pointerup", end);
    wrapper.addEventListener("pointercancel", end);
  }

  function addControls(entry) {
    const {wrapper} = entry;
    const handle = document.createElement("button");
    handle.type = "button";
    handle.className = "leonardo-object-resize";
    handle.setAttribute("aria-label", label("Resize"));

    const rotate = document.createElement("button");
    rotate.type = "button";
    rotate.className = "leonardo-rubric-rotate";
    rotate.textContent = "↻";
    rotate.title = label("Rotate rubric 90°");
    rotate.setAttribute("aria-label", rotate.title);
    rotate.addEventListener("click", () => {
      const page = wrapper.closest(".leonardo-page");
      if (!editable() || !page) return;
      const placement = origin(entry, page);
      commit(entry, {...placement, rotation: (placement.rotation + 90) % 360}, entry.size);
    });

    entry.handle = handle;
    entry.rotate = rotate;
    wrapper.append(handle, rotate);
    wrapper.addEventListener("pointerdown", event => beginGesture(event, entry));
    wrapper.addEventListener("focus", () => { if (editable()) select(entry); });
    wrapper.addEventListener("keydown", event => {
      if (event.target !== wrapper || !editable()) return;
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        select(entry);
      }
    });
  }

  function prepare(nextRoot, nextPayload) {
    const selectedID = selected?.fieldID;
    select(null);
    root = nextRoot;
    payload = nextPayload;
    const seen = new Set();
    fields = [];
    for (const wrapper of root.querySelectorAll(".leonardo-form-field[data-field]")) {
      const fieldID = wrapper.dataset.field, definition = payload.leonardo?.fields?.[fieldID];
      if (definition?.type !== "rubric" || seen.has(fieldID)) continue;
      seen.add(fieldID);
      const placement = definition.rubricPlacement;
      const entry = {wrapper, fieldID, placement, size: definition.rubricSize || {width: 180, height: 60}};
      if (placement) {
        const anchor = document.createElement("span");
        anchor.className = "leonardo-field-value";
        anchor.hidden = true;
        wrapper.before(anchor);
        wrapper.classList.add("leonardo-rubric-positioned");
        wrapper.style.left = `${placement.x}pt`;
        wrapper.style.top = `${placement.y}pt`;
        wrapper.style.rotate = `${placement.rotation}deg`;
        sizeField(entry, entry.size);
        wrapper.remove();
      }
      addControls(entry);
      fields.push(entry);
      if (editable() && fieldID === selectedID) select(entry);
    }
    setEditable(payload.allowsEditing);
  }

  function place() {
    for (const {wrapper, placement} of fields) {
      if (!placement) continue;
      const page = root.querySelector(`:scope > .leonardo-page[data-page="${placement.page}"]`);
      page?.append(wrapper);
    }
  }

  function setEditable(value) {
    if (!payload) return;
    payload.allowsEditing = value;
    if (!editable()) select(null);
    for (const {wrapper} of fields) {
      wrapper.classList.toggle("leonardo-rubric-layout-editable", !!editable());
      wrapper.tabIndex = editable() ? 0 : -1;
    }
  }

  window.LeonardoRubricPlacement = {
    prepare, place, setEditable,
    needsPages: () => fields.some(entry => entry.placement) || (editable() && fields.length > 0),
    lastPage: () => Math.max(1, ...fields.map(entry => entry.placement?.page || 1))
  };
})();
