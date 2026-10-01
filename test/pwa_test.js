const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const code = fs.readFileSync('public/service-worker.js', 'utf8');
function worker() {
  const handlers = {}, fetched = [], matched = [], cached = [];
  let offline = false;
  const context = {
    URL,
    self: {location: {origin: 'http://127.0.0.1:47391'}, addEventListener: (name, fn) => handlers[name] = fn, skipWaiting: async () => {}, clients: {claim: async () => {}}},
    caches: {open: async () => ({addAll: async paths => cached.push(...paths)}), keys: async () => [], match: async path => {matched.push(path); return 'offline page';}, delete: async () => {}},
    fetch: async request => {fetched.push(request.url); if (offline) throw Error('server stopped'); return 'live response';}
  };
  vm.runInNewContext(code, context);
  return {handlers, fetched, matched, cached, stop: () => offline = true};
}
test('install caches only the offline page and icons', async () => {
  const w = worker(); let pending;
  w.handlers.install({waitUntil: promise => pending = promise}); await pending;
  assert.deepEqual(w.cached, ['/offline.html', '/icons/sidecar-192.png', '/icons/sidecar-512.png']);
});
test('private navigation uses live network, with honest offline fallback only', async () => {
  const w = worker(); let reply;
  const event = {request: {method: 'GET', mode: 'navigate', url: 'http://127.0.0.1:47391/questions'}, respondWith: promise => reply = promise};
  w.handlers.fetch(event); assert.equal(await reply, 'live response'); assert.equal(w.matched.length, 0);
  w.stop(); w.handlers.fetch(event); assert.equal(await reply, 'offline page'); assert.deepEqual(w.matched, ['/offline.html']);
});
test('POST replies, revision endpoints and external requests are never intercepted', () => {
  const w = worker();
  for (const request of [
    {method: 'POST', mode: 'navigate', url: 'http://127.0.0.1:47391/questions/1/reply'},
    {method: 'GET', mode: 'cors', url: 'http://127.0.0.1:47391/sync-status'},
    {method: 'GET', mode: 'navigate', url: 'https://example.com/'}
  ]) w.handlers.fetch({request, respondWith: () => assert.fail('private request intercepted')});
  assert.equal(w.fetched.length, 0); assert.equal(w.matched.length, 0);
});
