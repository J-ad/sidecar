(() => {
  const MAX_BYTES = 10 * 1024 * 1024;
  const TYPES = new Set(["image/png", "image/jpeg", "image/gif", "image/webp"]);
  const pending = new Set();
  const failed = new Set();
  const status = () => document.getElementById("upload-status");
  function message(text, error = false) {
    const element = status();
    if (element) { element.textContent = text; element.classList.toggle("error", error); }
  }
  function buttons() {
    document.querySelectorAll("[data-todo-form] input[type=submit]").forEach(button => {
      button.disabled = pending.size > 0 || failed.size > 0;
    });
  }
  function rejection(file) {
    if (!TYPES.has(file.type)) return "Choose PNG, JPEG, GIF or WebP images.";
    if (file.size < 1 || file.size > MAX_BYTES) return "Images must be between 1 byte and 10 MB.";
    return null;
  }
  // Keep pasted web HTML as text/formatting; screenshots must be clipboard files.
  document.addEventListener("paste", event => {
    const editor = event.target.closest("trix-editor[data-upload-url]");
    const data = event.clipboardData;
    if (!editor || !data || data.files.length || !data.getData("text/html")) return;
    const html = new DOMParser().parseFromString(data.getData("text/html"), "text/html");
    html.querySelectorAll("img,iframe,object,embed,video,audio,svg,script,style,action-text-attachment,[data-trix-attachment]").forEach(node => node.remove());
    event.preventDefault();
    event.stopImmediatePropagation();
    editor.editor.insertHTML(html.body.innerHTML);
  }, true);
  document.addEventListener("trix-file-accept", event => {
    if (!event.target.dataset.uploadUrl) return;
    const error = rejection(event.file);
    if (error) { event.preventDefault(); message(error, true); }
  });
  document.addEventListener("trix-attachment-add", async event => {
    const attachment = event.attachment;
    const editor = event.target;
    if (!editor.dataset.uploadUrl || !attachment.file) return;
    pending.add(attachment); buttons(); message("Uploading screenshot…");
    try {
      const data = new FormData(); data.append("file", attachment.file);
      const response = await fetch(editor.dataset.uploadUrl, {
        method: "POST", body: data, credentials: "same-origin",
        headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "", "Accept": "application/json" }
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || "Upload failed.");
      attachment.setAttributes({ sgid: body.sgid, url: body.url, href: body.url,
        filename: body.filename, filesize: body.filesize, contentType: body.contentType });
      attachment.setUploadProgress(100);
      message("Screenshot uploaded locally.");
    } catch (error) {
      failed.add(attachment);
      message(`${error.message} Remove the failed image, then add it again to retry.`, true);
    } finally {
      pending.delete(attachment); buttons();
    }
  });
  document.addEventListener("trix-attachment-remove", event => {
    failed.delete(event.attachment); pending.delete(event.attachment); buttons();
    if (!pending.size && !failed.size) message("");
  });
  document.addEventListener("change", event => {
    if (!event.target.matches("[data-todo-images]")) return;
    const editor = document.getElementById("todo_notes_editor");
    for (const file of event.target.files) editor.editor.insertFile(file);
    event.target.value = "";
  });
  document.addEventListener("submit", event => {
    if (event.target.matches("[data-todo-form]") && (pending.size || failed.size)) {
      event.preventDefault(); message("Wait for uploads or remove failed images before saving.", true);
    }
  });
  document.addEventListener("turbo:before-cache", () => { pending.clear(); failed.clear(); });
})();
