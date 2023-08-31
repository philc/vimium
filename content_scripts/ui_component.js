class UIComponent {
  constructor(iframeUrl, className, handleMessage) {
    this.handleMessage = handleMessage;
    this.iframeElement = null;
    this.iframePort = null;
    this.showing = false;
    this.iframeFrameId = null;
    // TODO(philc): Make the @options object default to {} and remove the null checks.
    this.options = null;
    this.shadowDOM = null;

    const isDomTests = iframeUrl.includes("?dom_tests=true");

    DomUtils.documentReady(() => {
      const styleSheet = DomUtils.createElement("style");
      styleSheet.type = "text/css";
      // Default to everything hidden while the stylesheet loads.
      styleSheet.innerHTML = "iframe {display: none;}";

      // Fetch "content_scripts/vimium.css" from chrome.storage.session; the background page caches
      // it there.
      chrome.storage.session.get(
        "vimiumCSSInChromeStorage",
        (items) => styleSheet.innerHTML = items.vimiumCSSInChromeStorage,
      );

      this.iframeElement = DomUtils.createElement("iframe");
      Object.assign(this.iframeElement, {
        className,
        seamless: "seamless",
      });

      const shadowWrapper = DomUtils.createElement("div");
      // Prevent the page's CSS from interfering with this container div.
      shadowWrapper.className = "vimiumReset";
      // Firefox doesn't support createShadowRoot, so guard against its non-existance.
      // https://hacks.mozilla.org/2018/10/firefox-63-tricks-and-treats/ says Firefox 63 has enabled
      // Shadow DOM v1 by default
      if (shadowWrapper.attachShadow) {
        this.shadowDOM = shadowWrapper.attachShadow({ mode: "open" });
      } else {
        this.shadowDOM = shadowWrapper;
      }

      this.shadowDOM.appendChild(styleSheet);
      this.shadowDOM.appendChild(this.iframeElement);
      this.handleDarkReaderFilter();
      this.toggleIframeElementClasses("vimiumUIComponentVisible", "vimiumUIComponentHidden");

      // Open a port and pass it to the iframe via window.postMessage. We use an AsyncDataFetcher to
      // handle requests which arrive before the iframe (and its message handlers) have completed
      // initialization. See #1679.
      this.iframePort = new AsyncDataFetcher((setIframePort) => {
        // We set the iframe source and append the new element here (as opposed to above) to avoid a
        // potential race condition vis-a-vis the "load" event (because this callback runs on
        // "nextTick").
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
                    if ((event.target === window) && this.options && this.options.focus) {
                      this.hide(false);
                    }
                    // Continue propagating the event.
                    return true;
                  }),
                  true,
                );
                // Set the iframe's port, thereby rendering the UI component ready.
                setIframePort(port1);
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
    });
  }

  // This ensures that Vimium's UI elements (HUD, Vomnibar) honor the browser's light/dark theme
  // preference, even when the user is also using the DarkReader extension. DarkReader is the most
  // popular dark mode Chrome extension in use as of 2020.
  handleDarkReaderFilter() {
    const reverseFilterClass = "reverseDarkReaderFilter";

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

  toggleIframeElementClasses(removeClass, addClass) {
    this.iframeElement.classList.remove(removeClass);
    this.iframeElement.classList.add(addClass);
  }

  // Post a message (if provided), then call continuation (if provided). We wait for documentReady()
  // to ensure that the @iframePort set (so that we can use @iframePort.use()).
  postMessage(message = null, continuation = null) {
    if (!this.iframePort) {
      return;
    }

    this.iframePort.use(function (port) {
      if (message != null) {
        port.postMessage(message);
      }
      if (continuation) {
        continuation();
      }
    });
  }

  activate(options = null) {
    this.options = options;
    this.postMessage(this.options, () => {
      this.toggleIframeElementClasses("vimiumUIComponentHidden", "vimiumUIComponentVisible");
      if (this.options && this.options.focus) {
        this.iframeElement.focus();
      }
      this.showing = true;
    });
  }

  hide(shouldRefocusOriginalFrame) {
    // We post a non-message (null) to ensure that hide() requests cannot overtake activate()
    // requests.
    if (shouldRefocusOriginalFrame == null) shouldRefocusOriginalFrame = true;
    this.postMessage(null, () => {
      if (!this.showing) return;
      this.showing = false;
      this.toggleIframeElementClasses("vimiumUIComponentVisible", "vimiumUIComponentHidden");
      if (this.options && this.options.focus) {
        this.iframeElement.blur();
        if (shouldRefocusOriginalFrame) {
          if (this.options && (this.options.sourceFrameId != null)) {
            chrome.runtime.sendMessage({
              handler: "sendMessageToFrames",
              frameId: this.options.sourceFrameId,
              message: {
                handler: "focusFrame",
                forceFocusThisFrame: true,
              },
            });
          } else {
            Utils.nextTick(() => window.focus());
          }
        }
      }
      this.options = null;
      this.postMessage("hidden"); // Inform the UI component that it is hidden.
    });
  }
}

window.UIComponent = UIComponent;
