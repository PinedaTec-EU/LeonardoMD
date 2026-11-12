(() => {
  "use strict";

  // These names are application-owned. Document text never selects a script URL.
  const engines = Object.freeze({
    charts: "vega-engine.min.js",
    citations: "citation-engine.min.js"
  });
  const pending = new Map();
  const loadTimeoutMilliseconds = 10000;

  function load(name) {
    if (!Object.hasOwn(engines, name)) return Promise.reject(new Error("Unknown document engine"));
    if (pending.has(name)) return pending.get(name);
    const promise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      let settled = false;
      const finish = (error) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(timer);
        script.onload = null;
        script.onerror = null;
        if (error) {
          script.remove();
          reject(error);
        } else resolve();
      };
      const timer = window.setTimeout(() => finish(new Error("Document engine load timed out")), loadTimeoutMilliseconds);
      script.onload = () => finish();
      script.onerror = () => finish(new Error("Document engine could not be loaded"));
      script.src = `leonardo-resource://bundle/${engines[name]}`;
      document.head.appendChild(script);
    });
    pending.set(name, promise);
    return promise;
  }

  window.LeonardoExtensionEngines = Object.freeze({ load });
})();
