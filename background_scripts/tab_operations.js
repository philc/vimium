//
// Functions for opening URLs in tabs.
//

import * as bgUtils from "../background_scripts/bg_utils.js";
import "../lib/url_utils.js";

const chromeNewTabUrl = "about:newtab";

// Opens request.url in the current tab. If the URL is keywords, search for them in the default
// search engine. If the URL is a javascript: snippet, execute it in the current tab.
export async function openUrlInCurrentTab(request) {
  const urlStr = await UrlUtils.convertToUrl(request.url);
  if (urlStr == null) {
    // The requested destination is not a URL, so treat it like a search query.
    chrome.search.query({ text: request.url });
  } else if (UrlUtils.hasJavascriptProtocol(urlStr)) {
    // Note that when injecting JavaScript, it's subject to the site's CSP. Sites with strict CSPs
    // (like github.com, developer.mozilla.org) will raise an error when we try to run this code. See
    // https://github.com/philc/vimium/issues/4331.
    const scriptingArgs = {
      target: { tabId: request.tabId },
      func: (text) => {
        const prefix = "javascript:";
        text = text.slice(prefix.length).trim();
        // TODO(philc): Why do we try to double decode here? Discover and then document it.
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
      args: [urlStr],
    };
    if (!bgUtils.isFirefox()) {
      // The MAIN world -- where the webpage runs -- is less privileged than the ISOLATED world.
      // Specifying a world is required for Chrome, but not Firefox.
      // As of Firefox 118, specifying "MAIN" as the world is not yet supported.
      scriptingArgs.world = "MAIN";
    }
    chrome.scripting.executeScript(scriptingArgs);
  } else {
    // It's a regular URL.
    chrome.tabs.update(request.tabId, { url: urlStr });
  }
}

// Opens request.url in new tab and switches to it.
export async function openUrlInNewTab(request) {
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
      tabIndex = bgUtils.isFirefox() ? 9999 : null;
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
  return await chrome.tabs.create(tabConfig);
}

// Open request.url in new window and switch to it.
export async function openUrlInNewWindow(request) {
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
  await chrome.windows.create(winConfig);
}
