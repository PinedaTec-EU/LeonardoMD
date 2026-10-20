(() => {
  "use strict";
  let closeActive;
  const iso = date => `${String(date.getFullYear()).padStart(4, "0")}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
  const parse = value => {
    if (!/^\d{4}-\d\d-\d\d$/.test(value)) return null;
    const date = new Date(`${value}T12:00:00`);
    return Number.isFinite(date.getTime()) && iso(date) === value ? date : null;
  };
  const daysInMonth = month => {
    const last = new Date(month); last.setMonth(last.getMonth() + 1); last.setDate(0);
    return last.getDate();
  };
  window.LeonardoCalendar = {
    attach(input, wrapper) {
      const locale = input.lang || "en";
      const spanish = locale.toLowerCase().startsWith("es");
      const words = spanish ? ["Abrir calendario", "Mes anterior", "Mes siguiente", "Cerrar calendario"] : ["Open calendar", "Previous month", "Next month", "Close calendar"];
      input.placeholder ||= "YYYY-MM-DD";
      const button = (text, name, action) => {
        const element = document.createElement("button");
        element.type = "button"; element.textContent = text;
        element.setAttribute("aria-label", name); element.addEventListener("click", action);
        return element;
      };
      const panel = document.createElement("span");
      panel.className = "leonardo-calendar"; panel.hidden = true;
      panel.id = `${input.id}-calendar`;
      panel.setAttribute("role", "group");
      panel.setAttribute("aria-label", words[0]);
      const toggle = button("▦", words[0], () => panel.hidden ? open() : close());
      toggle.disabled = input.disabled;
      toggle.className = "leonardo-calendar-toggle";
      toggle.setAttribute("aria-controls", panel.id); toggle.setAttribute("aria-expanded", "false");
      const header = document.createElement("span"); header.className = "leonardo-calendar-header";
      const title = document.createElement("span"); title.setAttribute("aria-live", "polite");
      const grid = document.createElement("span"); grid.className = "leonardo-calendar-grid";
      let shown;
      function close() {
        panel.hidden = true; toggle.setAttribute("aria-expanded", "false");
        if (closeActive === close) closeActive = undefined;
      }
      function moveMonth(delta) {
        const next = new Date(shown); next.setMonth(next.getMonth() + delta);
        if (next.getFullYear() < 1 || next.getFullYear() > 9999) return;
        shown = next; render();
      }
      function render(focusDate) {
        title.textContent = new Intl.DateTimeFormat(locale, {month: "long", year: "numeric"}).format(shown);
        grid.replaceChildren();
        for (let index = 0; index < 7; index++) {
          const day = document.createElement("span"); day.className = "leonardo-calendar-weekday";
          day.textContent = new Intl.DateTimeFormat(locale, {weekday: "short"}).format(new Date(2024, 0, 1 + index));
          grid.append(day);
        }
        const offset = (shown.getDay() + 6) % 7;
        const count = daysInMonth(shown);
        for (let index = 0; index < offset; index++) grid.append(document.createElement("span"));
        for (let number = 1; number <= count; number++) {
          const date = new Date(shown); date.setDate(number);
          const value = iso(date);
          const day = button(String(number), new Intl.DateTimeFormat(locale, {dateStyle: "full"}).format(date), () => {
            if (input.disabled) return;
            input.value = value; input.dispatchEvent(new Event("input", {bubbles: true}));
            close(); input.focus();
          });
          day.dataset.date = value;
          day.setAttribute("aria-pressed", String(value === input.value));
          if (value === iso(new Date())) day.setAttribute("aria-current", "date");
          day.addEventListener("keydown", event => {
            const delta = {ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7}[event.key];
            if (delta === undefined) return;
            event.preventDefault(); date.setDate(date.getDate() + delta);
            if (date.getFullYear() < 1 || date.getFullYear() > 9999) return;
            shown = new Date(date); shown.setDate(1); render(iso(date));
          });
          grid.append(day);
        }
        if (focusDate) grid.querySelector(`[data-date="${focusDate}"]`)?.focus();
      }
      function open() {
        if (input.disabled) return;
        closeActive?.(); closeActive = close;
        const selected = parse(input.value) || new Date();
        shown = new Date(selected); shown.setDate(1);
        panel.hidden = false; toggle.setAttribute("aria-expanded", "true"); render(iso(selected));
      }
      header.append(button("‹", words[1], () => moveMonth(-1)), title, button("›", words[2], () => moveMonth(1)), button("×", words[3], () => { close(); toggle.focus(); }));
      panel.append(header, grid); wrapper.append(toggle, panel);
      wrapper.addEventListener("keydown", event => {
        if (event.key === "Escape" && !panel.hidden) { event.preventDefault(); close(); toggle.focus(); }
        if (event.altKey && event.key === "ArrowDown" && event.target === input) { event.preventDefault(); open(); }
      });
      wrapper.addEventListener("focusout", () => queueMicrotask(() => { if (!wrapper.contains(document.activeElement)) close(); }));
      input.addEventListener("input", () => { if (!panel.hidden) render(); });
    }
  };
})();
