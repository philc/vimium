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
    // (like github.com, developer.mozilla.org) will raise an error when we try to run this code.
    // See https://github.com/philc/vimium/issues/4331.
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
    // The requested destination is a regular URL.
    chrome.tabs.update(request.tabId, { url: urlStr });
  }
}

// Opens request.url in new tab and switches to it.
// Returns the created tab.
export async function openUrlInNewTab(request) {
  const urlStr = await UrlUtils.convertToUrl(request.url);
  const tabConfig = { windowId: request.tab.windowId };
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
  tabConfig.active = request.active ?? true;
  tabConfig.openerTabId = request.tab.id;

  let newTab;

  if (urlStr == null) {
    // The requested destination is not a URL, so treat it like a search query.
    //
    // The chrome.search.query API lets us open the search in a new tab, but it doesn't let us
    // control the precise position of that tab. So, we open a new blank tab using our position
    // parameter, and then execute the search in that tab.

    // In Chrome, if we create a blank tab and call chrome.search.query, the omnibar is focused,
    // which we don't want. To work around that, first create an empty page. This is not needed in
    // Firefox. And in fact, firefox doesn't support a data:text URL to the chrome.tab.create API.
    tabConfig.url = bgUtils.isFirefox() ? null : "data:text/html,<html></html>";
    newTab = await chrome.tabs.create(tabConfig);
    const query = request.url;
    await chrome.search.query({ text: query, tabId: newTab.id });
  } else {
    // The requested destination is a regular URL.
    if (urlStr != chromeNewTabUrl) {
      // Firefox does not support "about:newtab" in chrome.tabs.create.
      tabConfig.url = urlStr;
    }
    newTab = await chrome.tabs.create(tabConfig);
  }
  return newTab;
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
