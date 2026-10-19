(() => {
  "use strict";
  let payload = {}, root, changes = Object.create(null), sequence = 0;
  const controls = new Map();
  const label = key => payload.formLabels?.[key] || key;
  const valueText = (value, field) => {
    if (value === null || value === undefined) return "";
    if (field.type === "checkbox") return label(value ? "Yes" : "No");
    if (field.type === "select") return field.options?.find(o => o.value === value)?.label || String(value);
    return typeof value === "object" ? "" : String(value);
  };
  function post(name, body) { window.webkit?.messageHandlers?.[name]?.postMessage(body); }
  function snapshot() { return { source: payload.source || "", changes }; }
  function inputValue(input, field) {
    if (field.type === "checkbox") return input.checked;
    const text = input.value;
    if (field.type !== "number") return text;
    if (!text.trim()) return null;
    // Keep incomplete/invalid numeric drafts as text rather than losing keystrokes.
    const number = Number(text);
    return Number.isFinite(number) && /^[+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?$/i.test(text.trim()) ? number : text;
  }
  function synchronize(fieldID, value, origin) {
    for (const entry of controls.get(fieldID) || []) {
      entry.output.textContent = valueText(value, entry.field);
      if (entry.input && entry.input !== origin) {
        if (entry.field.type === "checkbox") entry.input.checked = value === true;
        else entry.input.value = value === null ? "" : String(value);
      }
    }
  }
  function commit(fieldID, field, input) {
    if (!payload.allowsFormFilling || field.readOnly) return;
    const value = inputValue(input, field);
    changes[fieldID] = value;
    synchronize(fieldID, value, input);
    post("leonardoForm", snapshot());
  }
  function makeInput(fieldID, field, value, id) {
    const input = document.createElement(field.type === "multiline" ? "textarea" : field.type === "select" ? "select" : "input");
    input.id = id;
    input.className = "leonardo-form-input";
    input.dataset.fieldInput = fieldID;
    if (field.type === "select") {
      const options = [{ value: "", label: "—" }, ...(field.options || [])];
      if (value && !options.some(option => option.value === value)) options.push({value: String(value), label: String(value)});
      for (const option of options) {
        const element = document.createElement("option");
        element.value = option.value; element.textContent = option.label || option.value;
        input.append(element);
      }
    } else if (field.type === "checkbox") {
      input.type = "checkbox";
      if (field.appearance === "switch") { input.setAttribute("role", "switch"); input.classList.add("leonardo-form-switch"); }
      input.checked = value === true;
    } else if (field.type !== "multiline") {
      input.type = ["date", "email", "url"].includes(field.type) ? field.type : "text";
      if (field.type === "number") input.inputMode = "decimal";
      if (field.type === "date" && value && !/^\d{4}-\d\d-\d\d$/.test(String(value))) input.type = "text";
    }
    if (field.type !== "checkbox") input.value = value === null || value === undefined ? "" : String(value);
    if (field.placeholder) input.placeholder = field.placeholder;
    input.setAttribute("aria-required", String(!!field.required));
    const event = ["select", "checkbox"].includes(field.type) ? "change" : "input";
    input.addEventListener(event, e => { if (!e.isComposing) commit(fieldID, field, input); });
    input.addEventListener("compositionend", () => commit(fieldID, field, input));
    return input;
  }
  window.LeonardoForms = {
    begin(nextPayload, nextRoot) {
      payload = nextPayload; root = nextRoot; changes = Object.create(null); controls.clear(); sequence = 0;
    },
    field(fieldID, field, value) {
      const wrapper = document.createElement("span");
      wrapper.className = "leonardo-field-value";
      wrapper.dataset.field = fieldID;
      const output = document.createElement("span");
      output.className = "leonardo-field-output";
      output.textContent = valueText(value, field) || "________";
      if (!payload.allowsFormFilling) { wrapper.append(output); return wrapper; }
      wrapper.classList.add("leonardo-form-field");
      const id = `leonardo-input-${++sequence}`;
      const header = document.createElement("span"); header.className = "leonardo-field-label";
      const caption = document.createElement("label"); caption.htmlFor = id;
      caption.textContent = (field.label || fieldID) + (field.required ? " *" : "");
      header.append(caption);
      const help = document.createElement("button"); help.type = "button"; help.className = "leonardo-field-help";
      help.textContent = "?"; help.setAttribute("aria-label", `${label("Help for")} ${field.label || fieldID}`);
      help.addEventListener("click", () => {
        root.querySelectorAll(".leonardo-field-help[aria-pressed]").forEach(button => button.removeAttribute("aria-pressed"));
        help.setAttribute("aria-pressed", "true");
        post("leonardoFieldHelp", {source: payload.source, fieldID});
      });
      header.append(help); wrapper.append(header);
      let input;
      if (field.readOnly) {
        wrapper.classList.add("leonardo-form-readonly");
        output.id = id;
        const badge = document.createElement("span"); badge.className = "leonardo-field-status"; badge.textContent = label("Read only");
        header.append(badge); wrapper.append(output);
      } else {
        input = makeInput(fieldID, field, value, id);
        wrapper.append(input, output);
      }
      const diagnostic = document.createElement("span"); diagnostic.id = `${id}-diagnostic`;
      diagnostic.className = "leonardo-field-diagnostic"; diagnostic.setAttribute("aria-live", "polite");
      if (input) input.setAttribute("aria-describedby", diagnostic.id);
      wrapper.append(diagnostic);
      const entries = controls.get(fieldID) || [];
      entries.push({input, output, diagnostic, field}); controls.set(fieldID, entries);
      return wrapper;
    },
    snapshot,
    showDiagnostics(diagnostics) {
      for (const [fieldID, entries] of controls) {
        const messages = diagnostics[fieldID] || [];
        for (const entry of entries) {
          entry.diagnostic.textContent = messages.map(message => label(message)).join(" ");
          entry.input?.setAttribute("aria-invalid", String(messages.length > 0));
        }
      }
    },
    setExporting(value) { root?.classList.toggle("leonardo-form-export", value); }
  };
})();
