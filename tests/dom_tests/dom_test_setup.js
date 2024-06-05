window.vimiumDomTestsAreRunning = true;

import * as shoulda from "../vendor/shoulda.js";

// Attach shoulda's functions -- like setup, context, should -- to the global namespace.
Object.assign(window, shoulda);
window.shoulda = shoulda;

document.addEventListener("DOMContentLoaded", async () => {
  isEnabledForUrl = true;
  await Settings.onLoaded();

  await HUD.init();
});
