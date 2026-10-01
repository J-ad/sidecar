// Optional developer verification: node --test test/auto_refresh_test.js
// No Node runtime or package dependencies are required by the application.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const script = fs.readFileSync('public/auto-refresh.js', 'utf8');
function harness(fields = []) {
  let tick, requests = 0, reloads = 0, interval;
  const handlers = new Map();
  const doc = {
    hidden: false, activeElement: {tagName: 'BODY'}, fields,
    querySelector: selector => selector === 'details[open]' ? null : {content: 'old'},
    querySelectorAll: () => doc.fields,
    addEventListener: (name, callback) => handlers.set(name, callback)
  };
  const state = {doc, event: (name, event = {}) => handlers.get(name)?.(event),
    tick: () => tick(), get requests() {return requests;}, get reloads() {return reloads;},
    get interval() {return interval;},
    fetch: async () => ({ok: true, json: async () => ({revision: 'new'})})};
  vm.runInNewContext(script, {document: doc, window: {}, clearInterval: () => {},
    setInterval: (callback, delay) => {tick = callback; interval = delay; return 1;},
    fetch: async (...args) => {requests++; return state.fetch(...args);},
    location: {reload: () => reloads++}});
  return state;
}
const input = (value = '', original = '') => ({tagName: 'INPUT', type: 'text', value, defaultValue: original});
test('untouched empty forms refresh, while a blurred draft waits until cleared', async () => {
  const url = input(); const h = harness([url]);
  assert.equal(h.interval, 10000);
  await h.tick(); assert.equal(h.reloads, 1);
  url.value = 'unfinished input';
  h.doc.activeElement = {tagName: 'BODY'};
  await h.tick(); assert.equal(h.requests, 1); assert.equal(h.reloads, 1);
  url.value = ''; await h.tick(); assert.equal(h.reloads, 2);
});
test('blurred search and changed select/checkbox values retain unsaved choices', async () => {
  const search = input('new draft', 'submitted query'); const h = harness([search]);
  await h.tick(); assert.equal(h.requests, 0);
  const select = {tagName: 'SELECT', multiple: false, value: 'new', options: [{value: 'old', defaultSelected: true}]};
  h.doc.fields = [select]; await h.tick(); assert.equal(h.requests, 0);
  h.doc.fields = [{tagName: 'INPUT', type: 'checkbox', checked: true, defaultChecked: false}];
  await h.tick(); assert.equal(h.requests, 0);
});
test('typing then blurring during the HTTP await prevents reload', async () => {
  const url = input(); const h = harness([url]); let resolve;
  h.fetch = () => new Promise(done => {resolve = done;});
  const pending = h.tick();
  url.value = 'unfinished'; h.doc.activeElement = {tagName: 'BODY'};
  resolve({ok: true, json: async () => ({revision: 'new'})});
  await pending; assert.equal(h.reloads, 0);
});
test('typing during the JSON await also prevents reload', async () => {
  const url = input(); const h = harness([url]); let resolve, ready;
  const jsonStarted = new Promise(done => {ready = done;});
  h.fetch = async () => ({ok: true, json: () => new Promise(done => {resolve = done; ready();})});
  const pending = h.tick(); await jsonStarted;
  url.value = 'unfinished'; resolve({revision: 'new'});
  await pending; assert.equal(h.reloads, 0);
});
test('source-filter navigation invalidates an old request; submitted fields start clean', async () => {
  const h = harness(); let resolve;
  h.fetch = () => new Promise(done => {resolve = done;});
  const pending = h.tick(); h.event('turbo:before-visit');
  h.doc.fields = [input('kept query', 'kept query')]; h.event('turbo:load');
  resolve({ok: true, json: async () => ({revision: 'new'})});
  await pending; assert.equal(h.reloads, 0);
  h.fetch = async () => ({ok: true, json: async () => ({revision: 'old'})});
  await h.tick(); assert.equal(h.requests, 2); assert.equal(h.reloads, 0);
});
test('single select with no explicit default and untouched empty forms are clean', async () => {
  const h = harness([input(), {tagName: 'SELECT', multiple: false, value: '', options: [{value: '', defaultSelected: false, disabled: false}]}]);
  await h.tick(); assert.equal(h.reloads, 1);
});
