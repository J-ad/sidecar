(() => {
  function setup() {
    document.querySelectorAll('.suggestion-panel').forEach(panel => {
      if (panel.dataset.bound) return;
      panel.dataset.bound = 'true';
      const generate = panel.querySelector('[data-generate-draft]');
      const cancel = panel.querySelector('[data-cancel-draft]');
      const use = panel.querySelector('[data-use-draft]');
      const status = panel.querySelector('[data-draft-status]');
      const preview = panel.querySelector('[data-draft-preview]');
      let stopped = false, draft = null, timer = null, generation = 0;
      const alive = () => panel.isConnected && !stopped;
      async function request(url, method, body) {
        const response = await fetch(url, {method, cache: 'no-store', headers: {'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content}, ...(body ? {body: JSON.stringify(body)} : {})});
        const data = await response.json();
        if (!response.ok) throw Error(data.message || 'Suggestion unavailable. No reply was sent.');
        return data;
      }
      function update(data, token) {
        if (!alive() || token !== generation) return;
        status.textContent = data.message || data.state;
        cancel.hidden = data.state !== 'running';
        generate.disabled = data.state === 'running' || data.state === 'stale' || data.state === 'unavailable';
        draft = data.state === 'ready' ? data.answers : null;
        use.hidden = !draft;
        preview.textContent = draft ? Object.entries(draft).map(([id, text]) => `${id}: ${text}`).join('\n\n') : '';
        if (data.state === 'running') timer = setTimeout(() => poll(token), 1000);
      }
      async function poll(token) {
        try { update(await request(panel.dataset.suggestionUrl, 'GET'), token); }
        catch (error) { if (alive() && token === generation) {status.textContent = error.message; cancel.hidden = true; generate.disabled = false;} }
      }
      generate.addEventListener('click', async () => {
        if (generate.disabled) return;
        const token = ++generation;
        clearTimeout(timer); draft = null; use.hidden = true; preview.textContent = ''; generate.disabled = true;
        status.textContent = 'Generating a draft…';
        try { update(await request(panel.dataset.suggestionUrl, 'POST', {context: panel.querySelector('[data-draft-context]').value}), token); }
        catch (error) { if (alive() && token === generation) {status.textContent = error.message; generate.disabled = false;} }
      });
      cancel.addEventListener('click', async () => {
        const token = ++generation;
        draft = null; use.hidden = true; preview.textContent = '';
        clearTimeout(timer);
        try { update(await request(panel.dataset.cancelUrl, 'POST', {}), token); }
        catch (error) { if (alive() && token === generation) status.textContent = error.message; }
      });
      use.addEventListener('click', () => {
        if (!draft) return;
        const fields = panel.closest('[data-agent-question]').querySelectorAll('textarea[name^="answers["]');
        fields.forEach(field => {
          const id = field.name.slice(8, -1);
          if (!field.disabled && !field.value.trim() && draft[id]) { field.value = draft[id]; field.dispatchEvent(new Event('input', {bubbles: true})); }
        });
        status.textContent = 'Draft copied into empty fields. Review and edit, then explicitly Send reply.';
      });
      document.addEventListener('turbo:before-cache', () => {stopped = true; clearTimeout(timer); delete panel.dataset.bound;}, {once: true});
    });
  }
  document.addEventListener('turbo:load', setup);
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup); else setup();
})();
