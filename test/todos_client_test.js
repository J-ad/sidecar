const { test } = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const source = fs.readFileSync("public/todos.js", "utf8");
function setup(fetch) {
  const handlers = new Map();
  const status = { textContent: "", classList: { toggle() {} } };
  const submit = { disabled: false };
  const editor = { dataset: { uploadUrl: "/todo_attachments" } };
  const document = {
    addEventListener(name, handler) { handlers.set(name, handler); },
    getElementById() { return status; },
    querySelector() { return { content: "csrf" }; },
    querySelectorAll() { return [submit]; }
  };
  class FormData { append() {} }
  vm.runInNewContext(source, { document, fetch, FormData, Set, Error });
  return { handlers, status, submit, editor };
}
const file = { type: "image/png", size: 100 };
function attachment() {
  return { file, setAttributes(value) { this.attributes = value; }, setUploadProgress(value) { this.progress = value; } };
}
test("a pending upload prevents saving until the local signed image is ready", async () => {
  let resolve;
  const env = setup(() => new Promise(done => { resolve = done; }));
  const image = attachment();
  const upload = env.handlers.get("trix-attachment-add")({ attachment: image, target: env.editor });
  assert.equal(env.submit.disabled, true);
  let prevented = false;
  env.handlers.get("submit")({ target: { matches: () => true }, preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  resolve({ ok: true, json: async () => ({ sgid: "signed", url: "/todo_attachments/signed", filename: "image.png", filesize: 100, contentType: "image/png" }) });
  await upload;
  assert.equal(env.submit.disabled, false);
  assert.equal(image.attributes.sgid, "signed");
  assert.equal(image.progress, 100);
});
test("failed uploads keep save blocked until the failed attachment is removed", async () => {
  const env = setup(async () => ({ ok: false, json: async () => ({ error: "Unsupported bytes" }) }));
  const image = attachment();
  await env.handlers.get("trix-attachment-add")({ attachment: image, target: env.editor });
  assert.equal(env.submit.disabled, true);
  assert.match(env.status.textContent, /Unsupported bytes/);
  env.handlers.get("trix-attachment-remove")({ attachment: image });
  assert.equal(env.submit.disabled, false);
});
test("network failure is visible and does not save an incomplete image", async () => {
  const env = setup(async () => { throw new Error("Offline"); });
  await env.handlers.get("trix-attachment-add")({ attachment: attachment(), target: env.editor });
  assert.equal(env.submit.disabled, true);
  assert.match(env.status.textContent, /Offline.*Remove/);
});
test("invalid type and excessive size are rejected before upload", () => {
  const env = setup(() => { throw new Error("must not fetch"); });
  for (const file of [{ type: "image/svg+xml", size: 100 }, { type: "image/png", size: 11 * 1024 * 1024 }]) {
    let prevented = false;
    env.handlers.get("trix-file-accept")({ target: env.editor, file, preventDefault() { prevented = true; } });
    assert.equal(prevented, true);
  }
});
