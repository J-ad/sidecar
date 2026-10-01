const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
function setup(respond) {
  const requests = [], timers = [];
  const controls = {};
  for (const name of ['generate-draft', 'cancel-draft', 'use-draft', 'draft-status', 'draft-preview', 'draft-context']) {
    controls[name] = {disabled: false, hidden: false, value: '', textContent: '', handlers: {}, addEventListener(type, fn) {this.handlers[type] = fn;}};
  }
  const fields = [{name: 'answers[q]', value: 'My own edited answer', disabled: false, dispatchEvent() {}}, {name: 'answers[r]', value: '', disabled: false, dispatchEvent() {}}];
  const panel = {dataset: {suggestionUrl: '/questions/1/suggestion', cancelUrl: '/questions/1/suggestion/cancel'}, isConnected: true, querySelector(selector) {return controls[selector.slice(6, -1)];}, closest() {return {querySelectorAll() {return fields;}};}};
  const document = {readyState: 'complete', querySelectorAll() {return [panel];}, querySelector() {return {content: 'csrf'};}, addEventListener() {}};
  vm.runInNewContext(fs.readFileSync('public/question-suggestions.js', 'utf8'), {document, Event: class {}, setTimeout: callback => timers.push(callback), clearTimeout() {}, fetch: async (url, options) => {
    requests.push({url, ...options});
    const body = await respond(url, options);
    return {ok: true, json: async () => body};
  }});
  return {controls, fields, requests, timers};
}
test('generation requires click, preview never sends and existing edits survive Use draft', async () => {
  const w = setup(async (_, options) => options.method === 'POST' ? {state: 'running'} : {state: 'ready', answers: {q: 'Suggested q', r: 'Suggested r'}, message: 'Draft by claude'});
  assert.equal(w.requests.length, 0);
  await w.controls['generate-draft'].handlers.click();
  await w.timers.pop()();
  assert.match(w.controls['draft-preview'].textContent, /Suggested r/);
  w.controls['use-draft'].handlers.click();
  assert.equal(w.fields[0].value, 'My own edited answer');
  assert.equal(w.fields[1].value, 'Suggested r');
  assert.equal(w.requests.filter(r => r.method === 'POST').length, 1);
  assert.equal(w.requests.some(r => r.url.includes('/reply')), false);
});
test('a pending status response cannot restore a draft after cancellation', async () => {
  let resolvePoll;
  const w = setup(async (url, options) => url.endsWith('/cancel') ? {state: 'cancelled'} : options.method === 'POST' ? {state: 'running'} : new Promise(resolve => resolvePoll = resolve));
  await w.controls['generate-draft'].handlers.click();
  const pending = w.timers.pop()();
  await w.controls['cancel-draft'].handlers.click();
  resolvePoll({state: 'ready', answers: {q: 'Late draft'}});
  await pending;
  assert.equal(w.controls['use-draft'].hidden, true);
  assert.equal(w.controls['draft-preview'].textContent, '');
  assert.equal(w.controls['draft-status'].textContent, 'cancelled');
});
