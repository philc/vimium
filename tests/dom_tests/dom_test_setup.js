window.vimiumDomTestsAreRunning = true

// Attach shoulda's functions, like setup, context, should, to the global namespace.
Object.assign(window, shoulda);

// Install frontend event handlers.
Frame.registerFrameId({chromeFrameId: 0});

getSelection = () =>
  window.getSelection().toString()

// Shoulda.js doesn't support async code, so we try not to use any.
Utils.nextTick = (func) => func()

document.addEventListener("DOMContentLoaded", () => HUD.init());
