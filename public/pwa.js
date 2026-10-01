if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker.js").catch(() => {
    // The dashboard remains usable when installation is unsupported.
  });
}
