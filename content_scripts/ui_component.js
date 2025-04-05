class UIComponent {
  iframeElement;
  iframePort;
  showing = false;
  // An optional message handler for handling messages from the iFrame.
  // TODO(philc): Rename to messageHandler.
  handleMessage;
  iframeFrameId;
  options = {};
  shadowDOM;

  constructor(iframeUrl, className, handleMessage) {
    this.handleMessage = handleMessage;
    this.init(iframeUrl, className);
  }

  async init(iframeUrl, className) {
    const isDomTests = iframeUrl.includes("?dom_tests=true");

    DomUtils.documentReady(() => {
      const styleSheet = DomUtils.createElement("style");
      styleSheet.type = "text/css";
      // Default to everything hidden while the stylesheet loads.
      styleSheet.innerHTML = "iframe {display: none;}";

      // Fetch "content_scripts/vimium.css" from chrome.storage.session; the background page caches
      // it there.
      chrome.storage.session.get("vimiumCSSInChromeStorage")
        .then((items) => styleSheet.innerHTML = items.vimiumCSSInChromeStorage);

      this.iframeElement = DomUtils.createElement("iframe");
      this.iframeElement.className = className;

      const shadowWrapper = DomUtils.createElement("div");
      // Prevent the page's CSS from interfering with this container div.
      shadowWrapper.className = "vimium-reset";
      this.shadowDOM = shadowWrapper.attachShadow({ mode: "open" });
      this.shadowDOM.appendChild(styleSheet);
      this.shadowDOM.appendChild(this.iframeElement);
      this.handleDarkReaderFilter();
      this.setIframeVisible(false);

      // Load the iframe and pass it a port via window.postMessage so we can communicate privately
      // with the iframe. Use a promise here so that requests to message this iframe's port will
      // block until it's ready. See #1679.
      let resolveFn;
      this.iframePort = new Promise((resolve, _reject) => {
        resolveFn = resolve;
      });

      this.iframeElement.src = chrome.runtime.getURL(iframeUrl);
      document.documentElement.appendChild(shadowWrapper);

      this.iframeElement.addEventListener("load", async () => {
        // Get vimiumSecret so the iframe can determine that our message isn't the page
        // impersonating us.
        const secret = (await chrome.storage.session.get("vimiumSecret")).vimiumSecret;
        const { port1, port2 } = new MessageChannel();
        // Outside of tests, target origin starts with chrome-extension://{vimium's-id}
        const targetOrigin = isDomTests ? "*" : chrome.runtime.getURL("");
        this.iframeElement.contentWindow.postMessage(secret, targetOrigin, [port2]);
        port1.onmessage = (event) => {
          let eventName = null;
          if (event) {
            eventName = (event.data ? event.data.name : undefined) || event.data;
          }

          switch (eventName) {
            case "uiComponentIsReady":
              // If this frame receives the focus, then hide the UI component.
              globalThis.addEventListener(
                "focus",
                forTrusted((event) => {
                  if ((event.target === window) && this.options.focus) {
                    this.hide(false);
                  }
                  // Continue propagating the event.
                  return true;
                }),
                true,
              );
              // Set the iframe's port, thereby rendering the UI component ready.
              // setIframePort(port1);
              resolveFn(port1);
              break;
            case "setIframeFrameId":
              this.iframeFrameId = event.data.iframeFrameId;
              break;
            case "hide":
              return this.hide();
            default:
              this.handleMessage(event);
          }
        };
      });
    });
  }

  // This ensures that Vimium's UI elements (HUD, Vomnibar) honor the browser's light/dark theme
  // preference, even when the user is also using the DarkReader extension. DarkReader is the most
  // popular dark mode Chrome extension in use as of 2020.
  handleDarkReaderFilter() {
    const reverseFilterClass = "vimium-reverse-dark-reader-filter";

    const reverseFilterIfExists = () => {
      // The DarkReader extension creates this element if it's actively modifying the current page.
      const darkReaderElement = document.getElementById("dark-reader-style");
      if (darkReaderElement && darkReaderElement.innerHTML.includes("filter")) {
        this.iframeElement.classList.add(reverseFilterClass);
      } else {
        this.iframeElement.classList.remove(reverseFilterClass);
      }
    };

    reverseFilterIfExists();

    const observer = new MutationObserver(reverseFilterIfExists);
    observer.observe(document.head, { characterData: true, subtree: true, childList: true });
  }

  setIframeVisible(visible) {
    const classes = this.iframeElement.classList;
    if (visible) {
      classes.remove("vimium-ui-component-hidden");
      classes.add("vimium-ui-component-visible");
    } else {
      classes.add("vimium-ui-component-hidden");
      classes.remove("vimium-ui-component-visible");
    }
  }

  async postMessage(message) {
    (await this.iframePort).postMessage(message);
  }

  async activate(options = {}) {
    this.options = options;
    await this.postMessage(this.options);
    this.setIframeVisible(true);
    if (this.options.focus) {
      this.iframeElement.focus();
    }
    this.showing = true;
  }

  async hide(shouldRefocusOriginalFrame) {
    if (shouldRefocusOriginalFrame == null) shouldRefocusOriginalFrame = true;

    await this.iframePort;
    if (!this.showing) return;
    this.showing = false;
    this.setIframeVisible(false);
    if (this.options.focus) {
      this.iframeElement.blur();
      if (shouldRefocusOriginalFrame) {
        if (this.options.sourceFrameId != null) {
          chrome.runtime.sendMessage({
            handler: "sendMessageToFrames",
            frameId: this.options.sourceFrameId,
            message: {
              handler: "focusFrame",
              forceFocusThisFrame: true,
            },
          });
        } else {
          Utils.nextTick(() => globalThis.focus());
        }
      }
    }
    this.options = {};
    this.postMessage("hidden"); // Inform the UI component that it is hidden.
  }
}

globalThis.UIComponent = UIComponent;
