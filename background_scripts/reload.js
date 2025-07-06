// Used as part of a debugging workflow when developing the extension.

const tabs = await chrome.tabs.query({});
// Clear the background page's console log, if its console window is open.
console.clear();
await chrome.runtime.reload();

// Chrome does not execute past this point. This is for Firefox-based browsers. Note that Chrome
// will not reload every tab that Vimium was open in. That must be done outside of Vimium, e.g. via
// an Applescript on Mac.

// Firefox will reload every tab as a result of chrome.runtime.reload(). However, the console
// on those pages does not get cleared for some reason, so we manually clear it.
for (const tab of tabs) {
  chrome.scripting.executeScript({
    target: { tabId: tab.id },
    func: () => {
      console.clear();
    },
  });
}

// We want to close the reload.html page as part of reloading the extension. In both Chrome and
// Firefox, the browser will automatically close every tab that's specific to this extension,
// including this page. However, in Firefox, if there's an error in manifest.json and the extension
// can't reload, then the extension's pages will not get closed, so close this page manually.
// globalThis.close();
