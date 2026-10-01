document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy-session]");
  if (!button) return;
  try { await navigator.clipboard.writeText(button.dataset.copySession); button.textContent = "Copied"; }
  catch { button.textContent = "Select the session ID to copy"; }
});
