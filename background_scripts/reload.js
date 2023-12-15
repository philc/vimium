// Used as part of a debugging workflow when developing the extension.
(async () => {
  await chrome.runtime.sendMessage({ handler: "reloadVimiumExtension" });
  // NOTE(philc): This page's window is supposed to automatically close when the extension reloads
  // itself, but I've noticed sometimes this fails.
  globalThis.close();
})();
