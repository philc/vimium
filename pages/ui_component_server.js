// Fetch the Vimium secret, register the port received from the parent window, and stop listening
// for messages on the window object. vimiumSecret is accessible only within the current instance of
// Vimium. So a malicious host page trying to register its own port can do no better than guessing.

function registerPort(event) {
  chrome.storage.session.get("vimiumSecret", function ({ vimiumSecret: secret }) {
    if (event.source !== globalThis.parent) return;
    if (event.data !== secret) {
      Utils.debugLog("ui_component_server: vimiumSecret is incorrect.");
      return;
    }
    UIComponentServer.portOpen(event.ports[0]);
    globalThis.removeEventListener("message", registerPort);
  });
}
globalThis.addEventListener("message", registerPort);

const UIComponentServer = {
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
    if (this.ownerPagePort) {
      this.ownerPagePort.postMessage(message);
    }
  },

  hide() {
    this.postMessage("hide");
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

globalThis.UIComponentServer = UIComponentServer;
