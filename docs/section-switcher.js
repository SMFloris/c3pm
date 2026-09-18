(() => {
  const sections = [...document.querySelectorAll(".doc-section")];
  const links = [...document.querySelectorAll("[data-section-link]")];

  if (sections.length === 0) return;

  function resolveSection(hash) {
    const id = decodeURIComponent(hash.replace(/^#/, ""));
    const target = id ? document.getElementById(id) : null;
    return target?.closest(".doc-section") || document.getElementById("overview");
  }

  function showSection(scrollToTarget) {
    const section = resolveSection(window.location.hash);
    const sectionName = section.dataset.section;

    for (const candidate of sections) {
      const active = candidate === section;
      candidate.classList.toggle("is-active", active);
      candidate.setAttribute("aria-hidden", String(!active));
    }

    for (const link of links) {
      const active = link.dataset.sectionLink === sectionName;
      link.classList.toggle("active", active);
      if (active) link.setAttribute("aria-current", "page");
      else link.removeAttribute("aria-current");
    }

    if (scrollToTarget) {
      requestAnimationFrame(() => {
        const id = decodeURIComponent(window.location.hash.replace(/^#/, ""));
        const target = document.getElementById(id) || section;
        target.scrollIntoView({ block: "start" });
      });
    }
  }

  window.addEventListener("hashchange", () => showSection(true));
  document.querySelector("[data-scroll-current]")?.addEventListener("click", (event) => {
    event.preventDefault();
    document.querySelector(".doc-section.is-active")?.scrollIntoView({ block: "start" });
  });
  showSection(Boolean(window.location.hash));
})();
