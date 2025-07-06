//
// These are functions for a page in a UIComponent iframe to communicate to its parent frame.
//

let ownerPagePort = null;
let handleMessage = null;

export async function registerPortWithOwnerPage(event) {
  if (event.source !== globalThis.parent) return;
  // The Vimium content script that's running on the parent page has access to this vimiumSecret
  // fetched from session storage, so if it matches, then we know that event.ports came from the
  // Vimium extension.
  const secret = (await chrome.storage.session.get("vimiumSecret")).vimiumSecret;
  if (event.data !== secret) {
    Utils.debugLog("ui_component_messenger.js: vimiumSecret is incorrect.");
    return;
  }
  openPort(event.ports[0]);
  // Once we complete a handshake with the parent page hosting this page's iframe, stop listening
  // for messages on the window object.
  globalThis.removeEventListener("message", registerPortWithOwnerPage);
}

// Used by unit tests.
export async function unregister() {
  ownerPagePort = null;
  handleMessage = null;
}

export function init() {
  globalThis.addEventListener("message", registerPortWithOwnerPage);
}

function openPort(port) {
  ownerPagePort = port;
  ownerPagePort.onmessage = async (event) => {
    if (handleMessage) {
      return await handleMessage(event);
    }
  };
  dispatchReadyEventWhenReady();
}

export function registerHandler(messageHandlerFn) {
  handleMessage = messageHandlerFn;
}

export function postMessage(data) {
  if (!ownerPagePort) return;
  ownerPagePort.postMessage(data);
}

// We require both that the DOM is ready and that the port has been opened before the UIComponent
// is ready. These events can happen in either order. We count them, and notify the content script
// when we've seen both.
let hasDispatchedReadyEvent = false;
function dispatchReadyEventWhenReady() {
  if (hasDispatchedReadyEvent) return;

  if (document.readyState === "loading") {
    globalThis.addEventListener("DOMContentLoaded", () => dispatchReadyEventWhenReady());
    return;
  }
  if (!ownerPagePort) return;

  if (globalThis.frameId != null) {
    postMessage({ name: "setIframeFrameId", iframeFrameId: globalThis.frameId });
  }
  hasDispatchedReadyEvent = true;
  postMessage({ name: "uiComponentIsReady" });
}
