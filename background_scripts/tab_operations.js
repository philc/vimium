//
// Methods for opening URLs in tabs.
//
// TODO(philc): Convert these to Promise-based APIs.

const chromeNewTabUrl = "about:newtab";

// Opens the url in the current tab.
// If the URL is a JavaScript snippet, execute that snippet in the current tab.
async function openUrlInCurrentTab(request) {
  // Note that when injecting JavaScript, it's subject to the site's CSP. Sites with strict CSPs
  // (like github.com, developer.mozilla.org) will raise an error when we try to run this code. See
  // https://github.com/philc/vimium/issues/4331.
  if (UrlUtils.hasJavascriptPrefix(request.url)) {
    const scriptingArgs = {
      target: { tabId: request.tabId },
      func: (text) => {
        const prefix = "javascript:";
        text = text.slice(prefix.length).trim();
        text = decodeURIComponent(text);
        try {
          text = decodeURIComponent(text);
        } catch {
          // Swallow
        }
        const el = document.createElement("script");
        el.textContent = text;
        document.head.appendChild(el);
      },
      args: [request.url],
    };

    if (!BgUtils.isFirefox()) {
      // The MAIN world -- where the webpage runs -- is less privileged than the ISOLATED world.
      // Specifying a world is required for Chrome, but not Firefox.
      // As of Firefox 118, specifying "MAIN" as the world is not yet supported.
      scriptingArgs.world = "MAIN";
    }

    chrome.scripting.executeScript(scriptingArgs);
  } else {
    chrome.tabs.update(request.tabId, { url: await UrlUtils.convertToUrl(request.url) });
  }
}

// Opens request.url in new tab and switches to it.
async function openUrlInNewTab(request, callback) {
  if (callback == null) {
    callback = function () {};
  }
  const tabConfig = {
    url: await UrlUtils.convertToUrl(request.url),
    active: true,
    windowId: request.tab.windowId,
  };

  const position = request.position;

  let tabIndex = null;

  switch (position) {
    case "start":
      tabIndex = 0;
      break;
    case "before":
      tabIndex = request.tab.index;
      break;
    // if on Chrome or on Firefox but without openerTabId, `tabs.create` opens a tab at the end.
    // but on Firefox and with openerTabId, it opens a new tab next to the opener tab
    case "end":
      tabIndex = BgUtils.isFirefox() ? 9999 : null;
      break;
    // "after" is the default case when there are no options.
    default:
      tabIndex = request.tab.index + 1;
  }
  tabConfig.index = tabIndex;

  if (request.active != null) {
    tabConfig.active = request.active;
  }
  // Firefox does not support "about:newtab" in chrome.tabs.create.
  if (tabConfig["url"] === chromeNewTabUrl) {
    delete tabConfig["url"];
  }

  tabConfig.openerTabId = request.tab.id;

  // clean position and active, so following `openUrlInNewTab(request)` will create a tab just next
  // to this new tab
  return chrome.tabs.create(
    tabConfig,
    (tab) => callback(Object.assign(request, { tab, tabId: tab.id, position: "", active: false })),
  );
}

// Opens request.url in new window and switches to it.
async function openUrlInNewWindow(request, callback) {
  if (callback == null) {
    callback = function () {};
  }
  const winConfig = {
    url: await UrlUtils.convertToUrl(request.url),
    active: true,
  };
  if (request.active != null) {
    winConfig.active = request.active;
  }
  // Firefox does not support "about:newtab" in chrome.tabs.create.
  if (tabConfig["url"] === chromeNewTabUrl) {
    delete winConfig["url"];
  }
  return chrome.windows.create(winConfig, callback);
}

export { openUrlInCurrentTab, openUrlInNewTab, openUrlInNewWindow };
