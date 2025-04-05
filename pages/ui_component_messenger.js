async function registerPortWithParentPage(event) {
  if (event.source !== globalThis.parent) return;
  // The Vimium content script that's running on the parent page has access to this vimiumsecret
  // fetched from session storage, so if it matches, then we know that event.ports came from the
  // Vimium extension.
  const secret = (await chrome.storage.session.get("vimiumSecret")).vimiumSecret;
  if (event.data !== secret) {
    Utils.debugLog("ui_component_messenger.js: vimiumSecret is incorrect.");
    return;
  }
  UIComponentMessenger.portOpen(event.ports[0]);
  // Once we complete a handshake with the parent page hosting this page's iframe, stop listening
  // for messages on the window object.
  globalThis.removeEventListener("message", registerPortWithParentPage);
}
globalThis.addEventListener("message", registerPortWithParentPage);

const UIComponentMessenger = {
  ownerPagePort: null,
  handleMessage: null,

  _portOpened: false,
  portOpen(ownerPagePort) {
    this.ownerPagePort = ownerPagePort;
    this.ownerPagePort.onmessage = async (event) => {
      if (this.handleMessage) {
        return await this.handleMessage(event);
      }
    };
    this._portOpened = true;
    this.dispatchReadyEventWhenReady();
  },

  registerHandler(handleMessage) {
    this.handleMessage = handleMessage;
  },

  postMessage(message) {
    if (!this.ownerPagePort) return;
    this.ownerPagePort.postMessage(message);
  },

  // We require both that the DOM is ready and that the port has been opened before the UI component
  // is ready. These events can happen in either order. We count them, and notify the content script
  // when we've seen both.
  _dispatchedReadyEvent: false,
  dispatchReadyEventWhenReady() {
    if (this._dispatchedReadyEvent) return;

    if (document.readyState === "loading") {
      globalThis.addEventListener("DOMContentLoaded", () => this.dispatchReadyEventWhenReady());
      return;
    }
    if (!this._portOpened) return;

    if (globalThis.frameId != null) {
      this.postMessage({ name: "setIframeFrameId", iframeFrameId: globalThis.frameId });
    }
    this._dispatchedReadyEvent = true;
    this.postMessage("uiComponentIsReady");
  },
};

globalThis.UIComponentMessenger = UIComponentMessenger;
