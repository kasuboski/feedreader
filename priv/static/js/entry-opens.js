(() => {
  function trackOpen(event) {
    if (event.type === "click" && event.button !== 0) return;
    if (event.type === "auxclick" && event.button !== 1) return;

    const target = event.target;
    if (!(target instanceof Element)) return;

    const link = target.closest("a[data-entry-id][data-open-target]");
    if (!link) return;

    const entryId = link.dataset.entryId;
    const openTarget = link.dataset.openTarget;
    if (!entryId || (openTarget !== "content" && openTarget !== "comments")) return;

    fetch(`/entry/${encodeURIComponent(entryId)}/open/${openTarget}`, {
      method: "POST",
      keepalive: true,
      credentials: "same-origin",
    }).catch(() => {});
  }

  // Observe opens before link/card handlers can stop propagation.
  document.addEventListener("click", trackOpen, { capture: true });
  document.addEventListener("auxclick", trackOpen, { capture: true });
})();
