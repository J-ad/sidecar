// Optional real-browser check: run against an isolated checkout with automatic readers disabled.
// PLAYWRIGHT_MODULE=/path/to/playwright node test/todos_browser_test.js
const assert = require("node:assert/strict");
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const url = process.env.TODOS_TEST_URL || "http://127.0.0.1:47392";
const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5f8AAAAASUVORK5CYII=", "base64");
(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.TODOS_CHROMIUM_PATH });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 1000 } });
    const errors = [];
    page.on("pageerror", error => errors.push(error.message));
    await page.goto(`${url}/todos/new`);
    await page.waitForFunction(() => !!document.querySelector("trix-editor")?.editor);
    const title = `Browser todo ${Date.now()}`;
    const screenshotPNG = Buffer.from(await page.evaluate(() => {
      const canvas = document.createElement("canvas"); canvas.width = 320; canvas.height = 160;
      const context = canvas.getContext("2d"); context.fillStyle = "#edf3ee"; context.fillRect(0, 0, 320, 160);
      context.fillStyle = "#203d31"; context.font = "20px sans-serif"; context.fillText("Screenshot fixture", 24, 72);
      return canvas.toDataURL("image/png").split(",")[1];
    }), "base64");
    await page.getByLabel("Title", { exact: true }).fill(title);
    await page.getByLabel("Link", { exact: true }).fill("https://example.com/task");
    await page.getByLabel("Checklist", { exact: true }).fill("Review\n[x] Reproduce");
    await page.locator("trix-editor").evaluate(element => element.editor.insertHTML('<div><strong>Browser notes</strong> <a href="https://example.com/notes">Reference</a></div>'));
    // Exercise Trix's real clipboard-file handler in Chromium using image clipboardData.
    // This does not alter the user's OS clipboard or test keyboard/system clipboard access.
    await page.locator("trix-editor").evaluate((element, bytes) => {
      const data = new DataTransfer();
      data.items.add(new File([new Uint8Array(bytes)], "clipboard.png", { type: "image/png" }));
      element.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }));
    }, Array.from(screenshotPNG));
    await page.waitForFunction(() => document.querySelector("#upload-status").textContent === "Screenshot uploaded locally.");
    await page.waitForFunction(() => document.querySelector('trix-editor img')?.complete && document.querySelector('trix-editor img')?.naturalWidth > 0);
    await page.getByLabel("Add screenshots", { exact: true }).setInputFiles({ name: "upload.png", mimeType: "image/png", buffer: screenshotPNG });
    await page.waitForFunction(() => document.querySelectorAll('trix-editor action-text-attachment').length === 2 || document.querySelectorAll('trix-editor figure').length === 2);
    await page.waitForFunction(() => document.querySelectorAll('trix-editor img').length === 2 && [...document.querySelectorAll('trix-editor img')].every(image => image.complete && image.naturalWidth > 0));
    await page.getByRole("button", { name: "Save todo", exact: true }).click();
    await page.waitForURL(/\/todos\/\d+$/);
    await page.reload();
    assert.equal(await page.locator("h1").textContent(), title);
    assert.equal(await page.locator('.todo-notes a[href="https://example.com/notes"]').textContent(), "Reference");
    assert.equal(await page.locator(".todo-notes img").count(), 2);
    await page.waitForFunction(() => [...document.querySelectorAll('.todo-notes img')].every(image => image.complete && image.naturalWidth > 0));
    await page.getByRole("checkbox").first().check();
    await page.locator(".todo-checklist li").first().getByRole("button", { name: "Save checkbox: Review" }).click();
    await page.waitForLoadState("networkidle");
    assert.equal(await page.getByRole("checkbox").first().isChecked(), true);
    await page.getByRole("button", { name: "Complete", exact: true }).click();
    await page.getByRole("button", { name: "Reopen", exact: true }).waitFor();
    await page.getByRole("button", { name: "Reopen", exact: true }).click();
    await page.getByRole("button", { name: "Complete", exact: true }).waitFor();
    await page.getByRole("link", { name: "Edit", exact: true }).click();
    await page.waitForFunction(() => document.querySelectorAll('trix-editor img').length === 2 && [...document.querySelectorAll('trix-editor img')].every(image => image.complete && image.naturalWidth > 0));
    await page.getByLabel("Title", { exact: true }).fill(`${title} edited`);
    await page.getByRole("button", { name: "Save todo", exact: true }).click();
    await page.waitForURL(/\/todos\/\d+$/);
    await page.waitForLoadState("networkidle");
    assert.equal(await page.locator(".todo-notes img").count(), 2);
    assert.equal(await page.locator("h1").count(), 1);
    assert.equal(await page.locator("h1").textContent(), `${title} edited`);
    assert.deepEqual(errors, []);
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await page.reload();
    await page.waitForLoadState("networkidle");
    await page.waitForFunction(() => [...document.querySelectorAll('.todo-notes img')].every(image => image.complete && image.naturalWidth > 0));
    await page.screenshot({ path: "tmp/todos-browser.png", fullPage: true });
    console.log(JSON.stringify({ result: "passed", todoURL: page.url(), imageCount: 2, clipboard: "real Chromium Trix ClipboardEvent with PNG file; OS keyboard clipboard untested", screenshot: "tmp/todos-browser.png" }));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
