(() => {
  const btn = document.getElementById('themeToggle');
  const root = document.documentElement;

  const getTheme = () => root.dataset.theme || 'light';
  const setTheme = (t) => {
    root.dataset.theme = t;
    try { localStorage.setItem('docforge.theme', t); } catch {}
  };

  if (btn) {
    btn.addEventListener('click', () => {
      setTheme(getTheme() === 'dark' ? 'light' : 'dark');
    });
  }

  // If a TOC link points to a <details>, open it.
  const openDetailsForHash = () => {
    const id = (location.hash || '').slice(1);
    if (!id) return;
    const el = document.getElementById(id);
    if (el && el.tagName && el.tagName.toLowerCase() === 'details') el.open = true;
  };

  window.addEventListener('hashchange', openDetailsForHash);
  openDetailsForHash();
})();

document.addEventListener("DOMContentLoaded", () => {
  const btn = document.getElementById("go-to-top");

  window.addEventListener("scroll", () => {
    btn.style.display = window.scrollY > 300 ? "block" : "none";
  });

  btn.addEventListener("click", () => {
    window.scrollTo({ top: 0, behavior: "smooth" });
  });
});

