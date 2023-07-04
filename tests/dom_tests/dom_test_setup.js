window.vimiumDomTestsAreRunning = true;

// Attach shoulda's functions -- like setup, context, should -- to the global namespace.
Object.assign(window, shoulda);

// Shoulda.js doesn't support async code, so we try not to use any.
// TODO(philc): This is outdated; we can consider using async tests now.
Utils.nextTick = (func) => func();

document.addEventListener("DOMContentLoaded", async () => {
  isEnabledForUrl = true;
  await Settings.onLoaded();

  await HUD.init();
});
