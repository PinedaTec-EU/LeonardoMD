(() => {
  "use strict";

  // Vega expressions normally use generated functions. The loader supplies a
  // vega-interpreter-backed engine so this adapter remains compatible with the
  // preview CSP (no unsafe-eval and no network access).
  const maximumSpecBytes = 256 * 1024;
  const maximumDepth = 32;
  const maximumNodes = 20_000;
  const maximumRows = 10_000;
  const maximumCompositionItems = 16;
  const maximumCompositionDepth = 4;
  const maximumLeafViews = 32;
  const maximumDimension = 4_096;
  const maximumStep = 256;
  const maximumSVGBytes = 4 * 1024 * 1024;
  const renderTimeoutMilliseconds = 15_000;
  const disallowedKeys = new Set([
    "__proto__", "constructor", "prototype",
    "events", "facet", "flatten", "generate", "href", "lookup", "on", "params",
    "repeat", "selection", "sequence", "signal", "signals", "url"
  ]);
  const compositionKeys = new Set(["concat", "hconcat", "layer", "vconcat"]);
  const states = new WeakMap();

  function getState(root) {
    let state = states.get(root);
    if (!state) {
      state = { generation: 0, ready: Promise.resolve() };
      states.set(root, state);
    }
    return state;
  }

  function isCurrent(state, generation) {
    return state.generation === generation;
  }

  function byteLength(value) {
    return new TextEncoder().encode(value).byteLength;
  }

  function validateSpec(value, path = "$", depth = 0, counters = { nodes: 0 }, compositionDepth = 0) {
    if (++counters.nodes > maximumNodes) {
      throw new Error("Chart specification is too complex.");
    }
    if (depth > maximumDepth) {
      throw new Error("Chart specification is too deeply nested.");
    }
    if (Array.isArray(value)) {
      if (path.endsWith(".values") && value.length > maximumRows) {
        throw new Error("Chart data contains too many rows.");
      }
      value.forEach((item, index) => validateSpec(item, `${path}[${index}]`, depth + 1, counters, compositionDepth));
      return;
    }
    if (!value || typeof value !== "object") return;
    Object.entries(value).forEach(([key, child]) => {
      if (disallowedKeys.has(key)) {
        throw new Error(`Chart property '${key}' is not allowed.`);
      }
      if (["width", "height"].includes(key) && typeof child === "number" &&
          (!Number.isFinite(child) || child < 0 || child > maximumDimension)) {
        throw new Error("Chart dimensions must be between 0 and 4096 pixels.");
      }
      if (["width", "height"].includes(key) && child && typeof child === "object" &&
          typeof child.step === "number" &&
          (!Number.isFinite(child.step) || child.step < 0 || child.step > maximumStep)) {
        throw new Error("Chart step dimensions must be between 0 and 256 pixels.");
      }
      let childCompositionDepth = compositionDepth;
      if (compositionKeys.has(key)) {
        childCompositionDepth += 1;
        if (childCompositionDepth > maximumCompositionDepth) {
          throw new Error("Chart composition is too deeply nested.");
        }
        if (Array.isArray(child) && child.length > maximumCompositionItems) {
          throw new Error("Chart composition contains too many views.");
        }
      }
      validateSpec(child, `${path}.${key}`, depth + 1, counters, childCompositionDepth);
    });
  }

  function countLeafViews(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return 1;
    for (const key of compositionKeys) {
      const children = value[key];
      if (Array.isArray(children)) {
        return children.reduce((total, child) => total + countLeafViews(child), 0);
      }
    }
    return 1;
  }

  function readSpec(holder) {
    const source = holder.dataset.vegaSource || "";
    if (byteLength(source) > maximumSpecBytes) {
      throw new Error("Chart specification exceeds the 256 KiB limit.");
    }
    let spec;
    try {
      spec = JSON.parse(source);
    } catch (_) {
      throw new Error("Chart specification must be valid JSON.");
    }
    if (!spec || typeof spec !== "object" || Array.isArray(spec)) {
      throw new Error("Chart specification must be a JSON object.");
    }
    validateSpec(spec);
    if (countLeafViews(spec) > maximumLeafViews) {
      throw new Error("Chart composition contains too many leaf views.");
    }
    return spec;
  }

  function setError(holder, message) {
    holder.dataset.state = "error";
    holder.classList.add("vega-lite-error");
    holder.setAttribute("role", "img");
    holder.setAttribute("aria-label", "Vega-Lite chart error");
    holder.textContent = message;
  }

  function sanitizeSVG(value) {
    return window.DOMPurify.sanitize(value, {
      USE_PROFILES: { svg: true },
      FORBID_TAGS: ["script", "foreignObject"],
      FORBID_ATTR: ["href", "xlink:href", "onload", "onclick", "onerror"]
    });
  }

  function placeholders(root) {
    return Array.from(root.querySelectorAll("pre code.language-vega-lite"), (code) => {
      const holder = document.createElement("div");
      holder.className = "vega-lite-placeholder";
      holder.dataset.vegaSource = code.textContent || "";
      holder.dataset.state = "waiting";
      holder.setAttribute("role", "img");
      holder.setAttribute("aria-label", "Vega-Lite chart loads");
      const pre = code.parentElement;
      if (pre) pre.replaceWith(holder);
      return holder;
    });
  }

  function engineParts(engine) {
    const value = engine || window.LeonardoVegaEngine;
    const vega = value?.vega || window.vega;
    const vegaLite = value?.vegaLite || window.vegaLite;
    const expressionInterpreter = value?.expressionInterpreter || vega?.expressionInterpreter;
    if (!vega || !vegaLite || !expressionInterpreter) {
      throw new Error("The Vega-Lite engine is unavailable.");
    }
    return { vega, vegaLite, expressionInterpreter };
  }

  async function renderHolder(holder, engine, isActive) {
    holder.dataset.state = "rendering";
    let view;
    try {
      const { vega, vegaLite, expressionInterpreter } = engineParts(engine);
      const spec = readSpec(holder);
      const compiled = vegaLite.compile(spec).spec;
      // `ast: true` is required by vega-interpreter. Passing the interpreter
      // explicitly is what keeps this path CSP-compliant.
      const runtime = vega.parse(compiled, null, { ast: true });
      view = new vega.View(runtime, {
        renderer: "svg",
        hover: false,
        expr: expressionInterpreter,
        logLevel: vega.Warn
      });
      const renderPromise = (async () => {
        await view.runAsync();
        return view.toSVG();
      })();
      let timeoutID;
      const timeoutPromise = new Promise((_, reject) => {
        timeoutID = window.setTimeout(() => reject(new Error("Chart rendering timed out.")), renderTimeoutMilliseconds);
      });
      let svg;
      try {
        svg = await Promise.race([renderPromise, timeoutPromise]);
      } finally {
        if (timeoutID) window.clearTimeout(timeoutID);
      }
      if (byteLength(svg) > maximumSVGBytes) {
        throw new Error("Rendered chart exceeds the 4 MiB limit.");
      }
      if (!isActive()) return;
      holder.innerHTML = sanitizeSVG(svg);
      holder.dataset.state = "rendered";
      holder.setAttribute("aria-label", typeof spec.description === "string" ? spec.description :
        (typeof spec.title === "string" ? spec.title : "Vega-Lite chart"));
      holder.classList.remove("vega-lite-error");
    } catch (error) {
      if (!isActive()) return;
      const message = error instanceof Error && error.message
        ? error.message
        : "Chart could not be rendered.";
      setError(holder, message);
    } finally {
      if (view) view.finalize();
    }
  }

  async function render(root, payload, options = {}) {
    const state = getState(root);
    const generation = ++state.generation;
    // Disabled extensions leave their fenced source untouched. This check
    // must precede placeholder replacement because the same adapter is called
    // for every render, including documents with extensions switched off.
    if (payload?.allowsVegaLite !== true) {
      state.ready = Promise.resolve();
      return state.ready;
    }
    const charts = placeholders(root);
    if (charts.length === 0) {
      state.ready = Promise.resolve();
      return state.ready;
    }

    state.ready = (async () => {
      let engine;
      try {
        engine = await options.loadEngine?.();
        if (!engine) engine = window.LeonardoVegaEngine;
      } catch (_) {
        if (isCurrent(state, generation)) {
          charts.forEach((holder) => setError(holder, "The Vega-Lite engine could not be loaded."));
        }
        return;
      }
      if (!isCurrent(state, generation)) return;
      await Promise.all(charts.map(async (holder) => {
        if (!isCurrent(state, generation)) return;
        await renderHolder(holder, engine, () => isCurrent(state, generation));
      }));
    })();
    return state.ready;
  }

  function whenReady(root) {
    return getState(root).ready;
  }

  function cancel(root) {
    const state = getState(root);
    state.generation += 1;
    state.ready = Promise.resolve();
  }

  window.LeonardoCharts = { render, whenReady, cancel };
})();
