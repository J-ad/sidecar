(() => {
  let generation = 0;
  let navigating = false;
  const dirtyField = (field) => {
    if (["checkbox", "radio"].includes(field.type)) return field.checked !== field.defaultChecked;
    if (field.tagName === "SELECT") {
      const options = Array.from(field.options);
      if (field.multiple) return options.some(option => option.selected !== option.defaultSelected);
      const original = options.find(option => option.defaultSelected) || options.find(option => !option.disabled);
      return field.value !== (original?.value || "");
    }
    return field.value !== field.defaultValue;
  };
  const paused = () => navigating || document.hidden || document.querySelector("details[open]") ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement?.tagName) ||
    Array.from(document.querySelectorAll('form input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="reset"]), form textarea, form select')).some(dirtyField);
  const navigatingAway = () => { navigating = true; generation++; };
  document.addEventListener("turbo:before-visit", navigatingAway);
  document.addEventListener("submit", navigatingAway);
  document.addEventListener("turbo:submit-end", event => { if (!event.detail.success) navigating = false; });
  const start = () => {
    clearInterval(window.panelRefreshTimer);
    navigating = false;
    generation++;
    let checking = false;
    window.panelRefreshTimer = setInterval(async () => {
      if (checking || paused()) return;
      const requestGeneration = generation;
      checking = true;
      try {
        const response = await fetch("/sync-status", {headers: {Accept: "application/json"}, cache: "no-store"});
        if (!response.ok) return;
        const state = await response.json();
        // Editing or navigation can begin while either network await is pending.
        if (requestGeneration !== generation || paused()) return;
        if (state.revision !== document.querySelector('meta[name="panel-revision"]')?.content) location.reload();
      } catch { /* Retain the current page while the local server is unavailable. */ }
      finally { checking = false; }
    }, 10000);
  };
  document.addEventListener("turbo:load", start);
  start();
})();
