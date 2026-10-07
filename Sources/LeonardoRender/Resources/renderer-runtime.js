(() => {
  "use strict";

  const payloadNode = document.getElementById("leonardo-payload");
  const root = document.getElementById("leonardo-markdown");
  if (!payloadNode || !root) return;

  let payload;
  try {
    payload = JSON.parse(payloadNode.textContent || "{}");
  } catch (_) {
    root.textContent = "The Markdown preview payload could not be read.";
    return;
  }

  const features = {
    mermaid: payload.allowsMermaid === true,
    math: payload.allowsMath === true
  };
  // Keep the complete Mermaid source as the cache key. A short hash is useful
  // for DOM ids, but it is not collision-safe as a cache key.
  const diagramCache = new Map();
  const diagramPromises = new Map();
  const diagramTimers = new Map();
  let diagramObserver;
  let scrollScheduled = false;
  let interactionsInstalled = false;
  let diagramSequence = 0;

  function postMessage(name, body) {
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[name];
    if (handler) handler.postMessage(body);
  }

  function setAppearance(appearance) {
    if (!appearance) return;
    const style = document.documentElement.style;
    style.setProperty("--ld-background", appearance.background || "#F8F8F5");
    style.setProperty("--ld-text", appearance.text || "#171717");
    style.setProperty("--ld-heading", appearance.heading || "#2B5C8A");
    style.setProperty("--ld-accent", appearance.accent || "#2B5C8A");
    style.setProperty("--ld-code-background", appearance.codeBackground || "#ECECE7");
    document.body.dataset.paperEffect = appearance.paperEffect || "plain";
  }

  function hash(value) {
    let result = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      result ^= value.charCodeAt(index);
      result = Math.imul(result, 16777619);
    }
    return (result >>> 0).toString(16);
  }

  function sanitizeHTML(value) {
    return window.DOMPurify.sanitize(value, {
      USE_PROFILES: { html: true },
      FORBID_TAGS: ["script", "style", "iframe", "object", "embed", "form"],
      FORBID_ATTR: ["srcdoc", "action", "formaction"]
    });
  }

  function renderTags() {
    if (!Array.isArray(payload.tags) || payload.tags.length === 0) return;
    const panel = document.createElement("nav");
    panel.className = "document-tags";
    panel.setAttribute("aria-label", "Document tags");
    payload.tags.forEach((tag) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "tag-pill";
      button.textContent = tag;
      button.addEventListener("click", () => postMessage("leonardoTag", tag));
      panel.appendChild(button);
    });
    root.before(panel);
  }

  function renderFrontMatter() {
    if (!payload.showFrontMatter || !payload.frontMatter || Object.keys(payload.frontMatter).length === 0) {
      return;
    }
    const panel = document.createElement("aside");
    panel.className = "front-matter";
    panel.setAttribute("aria-label", "Document metadata");
    const heading = document.createElement("h2");
    heading.textContent = "Metadata";
    panel.appendChild(heading);
    const list = document.createElement("dl");
    Object.entries(payload.frontMatter).forEach(([key, value]) => {
      const term = document.createElement("dt");
      term.textContent = key;
      const definition = document.createElement("dd");
      definition.textContent = value;
      list.append(term, definition);
    });
    panel.appendChild(list);
    root.before(panel);
  }

  function highlightCode() {
    if (!window.hljs) return;
    root.querySelectorAll("pre code").forEach((block) => {
      if (!block.classList.contains("language-mermaid")) {
        window.hljs.highlightElement(block);
      }
    });
  }

  function installHeadingAnchors() {
    const used = new Set();
    root.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach((heading) => {
      if (heading.id) {
        used.add(heading.id);
        return;
      }
      const source = (heading.textContent || "heading").trim().toLowerCase();
      const normalized = source.normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
      const base = normalized.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "heading";
      let id = base;
      let suffix = 2;
      while (used.has(id)) id = `${base}-${suffix++}`;
      heading.id = id;
      used.add(id);
    });
  }

  function splitMath(value) {
    const expression = /(\$\$[\s\S]+?\$\$|\\\[[\s\S]+?\\\]|\\\([\s\S]+?\\\)|\$[^$\n]+\$)/g;
    const pieces = [];
    let cursor = 0;
    let match;
    while ((match = expression.exec(value)) !== null) {
      if (match.index > cursor) pieces.push({ text: value.slice(cursor, match.index) });
      const token = match[0];
      const displayMode = token.startsWith("$$") || token.startsWith("\\[");
      const delimiterLength = token.startsWith("$$") || token.startsWith("\\[") || token.startsWith("\\(") ? 2 : 1;
      pieces.push({ math: token.slice(delimiterLength, -delimiterLength), displayMode });
      cursor = match.index + token.length;
    }
    if (cursor < value.length) pieces.push({ text: value.slice(cursor) });
    return pieces;
  }

  function renderMath() {
    if (!features.math || !window.katex) return;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const textNodes = [];
    let node;
    while ((node = walker.nextNode())) {
      if (node.parentElement && !node.parentElement.closest("pre, code, .katex")) {
        textNodes.push(node);
      }
    }
    textNodes.forEach((textNode) => {
      const pieces = splitMath(textNode.nodeValue || "");
      if (!pieces.some((piece) => piece.math !== undefined)) return;
      const fragment = document.createDocumentFragment();
      pieces.forEach((piece) => {
        if (piece.math === undefined) {
          fragment.appendChild(document.createTextNode(piece.text));
          return;
        }
        const span = document.createElement("span");
        span.className = "math-rendered";
        try {
          const rendered = window.katex.renderToString(piece.math, {
            displayMode: piece.displayMode,
            throwOnError: false,
            trust: false
          });
          span.innerHTML = window.DOMPurify.sanitize(rendered, {
            USE_PROFILES: { html: true, mathMl: true },
            ADD_TAGS: ["math", "semantics", "mrow", "annotation"]
          });
        } catch (_) {
          span.textContent = piece.text || "Math rendering failed";
        }
        fragment.appendChild(span);
      });
      textNode.parentNode.replaceChild(fragment, textNode);
    });
  }

  function scheduleDiagram(element) {
    if (!features.mermaid || !window.mermaid || ["rendered", "rendering", "error"].includes(element.dataset.state)) return;
    if (diagramTimers.has(element)) return;
    element.dataset.state = "queued";
    const timer = window.setTimeout(() => {
      diagramTimers.delete(element);
      renderDiagram(element);
    }, Math.max(0, payload.debounceMilliseconds || 80));
    diagramTimers.set(element, timer);
  }

  async function renderDiagram(element) {
    if (!features.mermaid || !window.mermaid) return;
    const timer = diagramTimers.get(element);
    if (timer) window.clearTimeout(timer);
    diagramTimers.delete(element);
    const source = element.dataset.mermaidSource || "";
    const key = source;
    const idKey = hash(source);
    if (diagramCache.has(key)) {
      element.innerHTML = diagramCache.get(key);
      element.dataset.state = "rendered";
      return;
    }
    const inFlight = diagramPromises.get(key);
    if (inFlight) {
      try {
        element.dataset.state = "rendering";
        element.innerHTML = await inFlight;
        element.dataset.state = "rendered";
      } catch (_) {
        element.classList.add("diagram-error");
        element.textContent = "Diagram could not be rendered.";
        element.dataset.state = "error";
      }
      return;
    }
    element.dataset.state = "rendering";
    const renderPromise = window.mermaid.render(`leonardo-diagram-${idKey}-${diagramSequence++}`, source)
      .then((result) => window.DOMPurify.sanitize(result.svg, { USE_PROFILES: { svg: true } }))
      .then((svg) => {
        diagramCache.set(key, svg);
        return svg;
      })
      .finally(() => diagramPromises.delete(key));
    diagramPromises.set(key, renderPromise);
    try {
      const svg = await renderPromise;
      element.innerHTML = svg;
      element.dataset.state = "rendered";
    } catch (_) {
      element.classList.add("diagram-error");
      element.textContent = "Diagram could not be rendered.";
      element.dataset.state = "error";
    }
  }

  function prepareMermaid() {
    if (!features.mermaid || !window.mermaid) return;
    if (diagramObserver) diagramObserver.disconnect();
    window.mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      htmlLabels: false,
      flowchart: { htmlLabels: false }
    });
    root.querySelectorAll("pre code.language-mermaid").forEach((code) => {
      const holder = document.createElement("div");
      holder.className = "mermaid-placeholder";
      holder.dataset.mermaidSource = code.textContent || "";
      holder.dataset.state = "waiting";
      holder.setAttribute("role", "img");
      holder.textContent = "Diagram loads when visible";
      code.parentElement.replaceWith(holder);
    });
    diagramObserver = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) scheduleDiagram(entry.target);
      });
    }, { rootMargin: "600px 0px" });
    root.querySelectorAll(".mermaid-placeholder").forEach((element) => diagramObserver.observe(element));
  }

  async function waitForDocumentAssets() {
    root.querySelectorAll("img").forEach((image) => { image.loading = "eager"; });
    const imageWaiters = Array.from(root.querySelectorAll("img")).map((image) => {
      if (image.complete && image.naturalWidth > 0) return Promise.resolve();
      return new Promise((resolve, reject) => {
        let settled = false;
        const timer = window.setTimeout(() => {
          settle();
          reject(new Error(`Image load timed out: ${image.currentSrc || image.src || "(unnamed)"}`));
        }, 2000);
        const settle = () => {
          if (settled) return;
          settled = true;
          window.clearTimeout(timer);
          image.removeEventListener("load", loaded);
          image.removeEventListener("error", failed);
        };
        const loaded = () => {
          if (image.naturalWidth > 0) {
            settle();
            resolve();
          } else {
            settle();
            reject(new Error(`Image loaded without pixels: ${image.currentSrc || image.src || "(unnamed)"}`));
          }
        };
        const failed = () => {
          settle();
          reject(new Error(`Image failed to load: ${image.currentSrc || image.src || "(unnamed)"}`));
        };
        image.addEventListener("load", loaded, { once: true });
        image.addEventListener("error", failed, { once: true });
        // An image can complete between the initial check and listener setup.
        if (image.complete) loaded();
      });
    });
    await Promise.all(imageWaiters);
    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready.catch(() => {});
    }
  }

  async function renderAllDiagrams() {
    if (features.mermaid && window.mermaid) {
      const diagrams = Array.from(root.querySelectorAll(".mermaid-placeholder"));
      await Promise.all(diagrams.map((element) => renderDiagram(element)));
    }
    await waitForDocumentAssets();
  }

  function emitScrollProgress() {
    scrollScheduled = false;
    const documentElement = document.documentElement;
    const maximum = Math.max(1, documentElement.scrollHeight - window.innerHeight);
    postMessage("leonardoScroll", {
      fraction: Math.min(1, Math.max(0, window.scrollY / maximum)),
      top: window.scrollY,
      height: documentElement.scrollHeight
    });
  }

  function installInteractions() {
    if (interactionsInstalled) return;
    interactionsInstalled = true;
    root.addEventListener("click", (event) => {
      const target = event.target instanceof Element ? event.target.closest("a[href]") : null;
      if (!target) return;
      event.preventDefault();
      postMessage("leonardoLink", { href: target.getAttribute("href") || "" });
    });
    window.addEventListener("scroll", () => {
      if (scrollScheduled) return;
      scrollScheduled = true;
      window.requestAnimationFrame(emitScrollProgress);
    }, { passive: true });
  }

  function renderDocument() {
    const renderStart = performance.now();
    setAppearance(payload.appearance);
    if (diagramObserver) diagramObserver.disconnect();
    diagramTimers.forEach((timer) => window.clearTimeout(timer));
    diagramTimers.clear();
    document.querySelectorAll("body > .front-matter, body > .document-tags").forEach((panel) => panel.remove());
    try {
      const rendered = window.marked.parse(payload.markdown || "", { gfm: true, breaks: false });
      root.innerHTML = sanitizeHTML(rendered);
      installHeadingAnchors();
      root.querySelectorAll("img").forEach((image) => {
        image.loading = "lazy";
        image.decoding = "async";
      });
      renderFrontMatter();
      renderTags();
      highlightCode();
      renderMath();
      prepareMermaid();
      installInteractions();
      postMessage("leonardoReady", {
        mermaid: features.mermaid,
        math: features.math,
        durationMs: performance.now() - renderStart
      });
    } catch (_) {
      root.textContent = "The Markdown preview could not be rendered.";
    }
  }

  window.LeonardoPreview = {
    setAppearance,
    updateContent(nextPayload) {
      if (!nextPayload || typeof nextPayload.markdown !== "string") return;
      payload = Object.assign(payload, nextPayload);
      renderDocument();
    },
    renderAllDiagrams,
    scrollToAnchor(anchor) {
      const element = document.getElementById(anchor);
      if (element) element.scrollIntoView({ behavior: "smooth", block: "start" });
    },
    scrollToFraction(fraction) {
      const maximum = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
      window.scrollTo({ top: Math.max(0, Math.min(1, fraction)) * maximum, behavior: "auto" });
    }
  };

  renderDocument();
})();
