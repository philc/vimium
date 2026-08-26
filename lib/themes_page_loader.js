// Loads the user's selected theme into this extension page, by appending a themed copy of each of
// the page's own stylesheets to the end of <head>. The appended stylesheets override the defaults
// because they come later in the cascade. This file is included by every extension page which
// displays Vimium UI. It must be loaded after lib/themes.js.
(() => {
  if (globalThis.chrome?.storage?.sync == null) return;
  if (globalThis.Themes == null) {
    throw new Error("lib/themes_page_loader.js requires lib/themes.js to be loaded first.");
  }

  const extensionOrigin = chrome.runtime.getURL("");
  let appliedTheme = null;

  const apply = async () => {
    const values = await chrome.storage.sync.get("theme");
    let theme = values.theme ?? Themes.defaultTheme;
    if (!Themes.isValidTheme(theme)) theme = Themes.defaultTheme;
    if (theme === appliedTheme) return;
    appliedTheme = theme;

    for (const el of document.querySelectorAll("link[data-vimium-theme]")) {
      el.remove();
    }
    if (theme === Themes.defaultTheme) return;

    for (const link of document.querySelectorAll("link[rel=stylesheet]")) {
      if (!link.href.startsWith(extensionOrigin)) continue;
      const filePath = decodeURI(link.href.slice(extensionOrigin.length));
      if (!Themes.themedFilePaths.includes(filePath)) continue;
      const themedLink = document.createElement("link");
      themedLink.rel = "stylesheet";
      themedLink.href = chrome.runtime.getURL(Themes.getThemePath(theme, filePath));
      themedLink.setAttribute("data-vimium-theme", theme);
      document.head.appendChild(themedLink);
    }
  };

  apply();
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area == "sync" && changes.theme != null) apply();
  });
})();
