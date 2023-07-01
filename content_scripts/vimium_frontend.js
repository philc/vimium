//
// This content script must be run prior to domReady so that we perform some operations very early.
//

const root = {};
// On Firefox, sometimes the variables assigned to window are lost (bug 1408996), so we reinstall them.
// NOTE(mrmr1993): This bug leads to catastrophic failure (ie. nothing works and errors abound).
DomUtils.documentReady(function () {
  Object.assign(window, root);
});

let isEnabledForUrl = true;
const isIncognitoMode = chrome.extension.inIncognitoContext;
let normalMode = null;

// We track whther the current window has the focus or not.
const windowIsFocused = (function () {
  let windowHasFocus = null;
  DomUtils.documentReady(() => windowHasFocus = document.hasFocus());
  window.addEventListener(
    "focus",
    forTrusted(function (event) {
      if (event.target === window) {
        windowHasFocus = true;
      }
      return true;
    }),
    true,
  );
  window.addEventListener(
    "blur",
    forTrusted(function (event) {
      if (event.target === window) {
        windowHasFocus = false;
      }
      return true;
    }),
    true,
  );
  return () => windowHasFocus;
})();

// This is set by initializeFrame. We can only get this frame's ID from the background page.
let frameId = null;

// If an input grabs the focus before the user has interacted with the page, then grab it back (if
// the grabBackFocus option is set).
class GrabBackFocus extends Mode {
  constructor() {
    super();
    let listener;
    const exitEventHandler = () => {
      return this.alwaysContinueBubbling(() => {
        this.exit();
        chrome.runtime.sendMessage({
          handler: "sendMessageToFrames",
          message: { name: "userIsInteractingWithThePage" },
        });
      });
    };

    super.init({
      name: "grab-back-focus",
      keydown: exitEventHandler,
    });

    // True after we've grabbed back focus to the page and logged it via console.log , so web devs
    // using Vimium don't get confused.
    this.logged = false;

    this.push({
      _name: "grab-back-focus-mousedown",
      mousedown: exitEventHandler,
    });

    if (this.modeIsActive) {
      if (Settings.get("grabBackFocus")) {
        this.push({
          _name: "grab-back-focus-focus",
          focus: (event) => this.grabBackFocus(event.target),
        });
        // An input may already be focused. If so, grab back the focus.
        if (document.activeElement) {
          this.grabBackFocus(document.activeElement);
        }
      } else {
        this.exit();
      }
    }

    // This mode is active in all frames. A user might have begun interacting with one frame without
    // other frames detecting this. When one GrabBackFocus mode exits, we broadcast a message to
    // inform all GrabBackFocus modes that they should exit; see #2296.
    chrome.runtime.onMessage.addListener(
      listener = ({ name }) => {
        if (name === "userIsInteractingWithThePage") {
          chrome.runtime.onMessage.removeListener(listener);
          if (this.modeIsActive) {
            this.exit();
          }
        }
        // We will not be calling sendResponse.
        return false;
      },
    );
  }

  grabBackFocus(element) {
    if (!DomUtils.isFocusable(element)) {
      return this.continueBubbling;
    }

    if (!this.logged && (element !== document.body)) {
      this.logged = true;
      if (!window.vimiumDomTestsAreRunning) {
        console.log("An auto-focusing action on this page was blocked by Vimium.");
      }
    }
    element.blur();
    return this.suppressEvent;
  }
}

// Pages can load new content dynamically and change the displayed URL using history.pushState.
// Since this can often be indistinguishable from an actual new page load for the user, we should
// also re-start GrabBackFocus for these as well. This fixes issue #1622.
handlerStack.push({
  _name: "GrabBackFocus-pushState-monitor",
  click(event) {
    // If a focusable element is focused, the user must have clicked on it. Retain focus and bail.
    if (DomUtils.isFocusable(document.activeElement)) {
      return true;
    }

    let target = event.target;

    while (target) {
      // Often, a link which triggers a content load and url change with javascript will also have
      // the new url as it's href attribute.
      if (
        (target.tagName === "A") &&
        (target.origin === document.location.origin) &&
        // Clicking the link will change the url of this frame.
        ((target.pathName !== document.location.pathName) ||
          (target.search !== document.location.search)) &&
        (["", "_self"].includes(target.target) ||
          ((target.target === "_parent") && (window.parent === window)) ||
          ((target.target === "_top") && (window.top === window)))
      ) {
        return new GrabBackFocus();
      } else {
        target = target.parentElement;
      }
    }
    return true;
  },
});

const installModes = function () {
  // Install the permanent modes. The permanently-installed insert mode tracks focus/blur events,
  // and activates/deactivates itself accordingly.
  normalMode = new NormalMode();
  normalMode.init();
  // Initialize components upon which normal mode depends.
  Scroller.init();
  FindModeHistory.init();
  new InsertMode({ permanent: true });
  if (isEnabledForUrl) {
    new GrabBackFocus();
  }
  // Return the normalMode object (for the tests).
  return normalMode;
};

//
// Complete initialization work that should be done prior to DOMReady.
//
const initializePreDomReady = async function () {
  // TODO(philc): When the extension is disabled, deactivate the content script. We used to do this
  // by listening on the port.disconnect fn, but we no longer use ports.
  // Disable the content scripts the page is unloaded
  window.addEventListener(
    "unload",
    forTrusted(function (event) {
      if (event.target === window) {
        onUnload();
      }
    }),
    true,
  );

  // NOTE(philc): I'm blocking further Vimium initialization on this, for simplicity. If necessary
  // we could allow other tasks to run concurrently.
  await Settings.onLoaded();
  installListeners();
  checkIfEnabledForUrl(document.hasFocus());

  const requestHandlers = {
    isWindowFocused(request, sender) {
      return windowIsFocused();
    },
    focusFrame(request) {
      focusThisFrame(request);
    },
    getScrollPosition(ignoredA, ignoredB) {
      if (DomUtils.isTopFrame()) {
        return { scrollX: window.scrollX, scrollY: window.scrollY };
      }
    },
    setScrollPosition,
    checkEnabledAfterURLChange,
    runInTopFrame({ sourceFrameId, registryEntry }) {
      if (DomUtils.isTopFrame()) {
        return NormalModeCommands[registryEntry.command](sourceFrameId, registryEntry);
      }
    },
    linkHintsMessage(request, sender) {
      return HintCoordinator[request.messageType](request, sender);
    },
    showMessage(request) {
      HUD.showForDuration(request.message, 2000);
    },
    executeScript(request) {
      // TODO(philc): Can we remove this return?
      return DomUtils.injectUserScript(request.script);
    },
  };

  Utils.addChromeRuntimeOnMessageListener(async function (request, sender) {
    Utils.debugLog("Vimium frontend: chrome.runtime.onMessage", request);
    request.isTrusted = true;
    // TODO(philc): Clean up the difference between name and handler.
    // Some request are handled elsewhere; ignore them too.
    const shouldHandleMessage = request.name !== "userIsInteractingWithThePage" &&
      (isEnabledForUrl ||
        ["checkEnabledAfterURLChange", "runInTopFrame"].includes(request.name));
    const result = shouldHandleMessage
      ? await requestHandlers[request.name](request, sender)
      : null;
    return result;
  });
};

// If our extension gets uninstalled, reloaded, or updated, the content scripts for the old version
// become orphaned: they remain running but cannot communicate with the background page or invoke
// most extension APIs. There is no Chrome API to be notified of this event, so we test for it every
// time a keystroke is pressed before we act on that keystroke. https://stackoverflow.com/a/64407849
const extensionHasBeenUnloaded = () => chrome.runtime?.id == null;

// Wrapper to install event listeners.  Syntactic sugar.
const installListener = (element, event, callback) => {
  element.addEventListener(
    event,
    forTrusted(function () {
      // TODO(philc): I think this workaround can be removed?
      if (typeof global === "undefined" || global === null) { // See #2800.
        Object.assign(window, root);
      }
      if (extensionHasBeenUnloaded()) {
        console.log("Vimium extension has been unloaded. Unloading content script.");
        onUnload();
        return;
      }
      if (isEnabledForUrl) {
        return callback.apply(this, arguments);
      } else {
        return true;
      }
    }),
    true,
  );
};

//
// Installing or uninstalling listeners is error prone. Instead we elect to check isEnabledForUrl
// each time so we know whether the listener should run or not.
// Run this as early as possible, so the page can't register any event handlers before us.
// Note: We install the listeners even if Vimium is disabled. See comment in commit
// 6446cf04c7b44c3d419dc450a73b60bcaf5cdf02.
//
const installListeners = Utils.makeIdempotent(function () {
  // Key event handlers fire on window before they do on document. Prefer window for key events so
  // the page can't set handlers to grab the keys before us.
  const events = ["keydown", "keypress", "keyup", "click", "focus", "blur", "mousedown", "scroll"];
  for (const type of events) {
    // TODO(philc): Can we remove this extra closure?
    ((type) => installListener(window, type, (event) => handlerStack.bubbleEvent(type, event)))(
      type,
    );
  }
  installListener(
    document,
    "DOMActivate",
    (event) => handlerStack.bubbleEvent("DOMActivate", event),
  );
});

// Whenever we get the focus, check if we should be enabled.
const onFocus = forTrusted(function (event) {
  if (event.target === window) {
    checkIfEnabledForUrl(true);
  }
});

// We install these listeners directly (that is, we don't use installListener) because we still need
// to receive events when Vimium is not enabled.
window.addEventListener("focus", onFocus, true);
window.addEventListener("hashchange", checkEnabledAfterURLChange, true);

const initializeOnDomReady = () => {
  // Tell the background page we're in the domReady state.
  chrome.runtime.sendMessage({ handler: "domReady" });
};

const onUnload = Utils.makeIdempotent(() => {
  HintCoordinator.exit({ isSuccess: false });
  handlerStack.reset();
  isEnabledForUrl = false;
  window.removeEventListener("focus", onFocus, true);
  window.removeEventListener("hashchange", checkEnabledAfterURLChange, true);
});

const setScrollPosition = ({ scrollX, scrollY }) =>
  DomUtils.documentReady(function () {
    if (DomUtils.isTopFrame()) {
      Utils.nextTick(function () {
        window.focus();
        document.body.focus();
        if ((scrollX > 0) || (scrollY > 0)) {
          Marks.setPreviousPosition();
          window.scrollTo(scrollX, scrollY);
        }
      });
    }
  });

const flashFrame = (function () {
  let highlightedFrameElement = null;

  return function () {
    if (highlightedFrameElement == null) {
      // TODO(philc): Make this a regular if body, not a closure.
      highlightedFrameElement = (function () {
        // Create a shadow DOM wrapping the frame so the page's styles don't interfere with ours.

        highlightedFrameElement = DomUtils.createElement("div");
        // Firefox doesn't support createShadowRoot, so guard against its non-existance.
        // https://hacks.mozilla.org/2018/10/firefox-63-tricks-and-treats/ says
        // Firefox 63 has enabled Shadow DOM v1 by default
        const _shadowDOM = highlightedFrameElement.attachShadow
          ? highlightedFrameElement.attachShadow({ mode: "open" })
          : highlightedFrameElement;

        // Inject stylesheet.
        const _styleSheet = DomUtils.createElement("style");
        _styleSheet.innerHTML = `@import url(\"${
          chrome.runtime.getURL("content_scripts/vimium.css")
        }\");`;
        _shadowDOM.appendChild(_styleSheet);

        const _frameEl = DomUtils.createElement("div");
        _frameEl.className = "vimiumReset vimiumHighlightedFrame";
        _shadowDOM.appendChild(_frameEl);

        return highlightedFrameElement;
      })();
    }

    document.documentElement.appendChild(highlightedFrameElement);
    Utils.setTimeout(200, () => highlightedFrameElement.remove());
  };
})();

//
// Called from the backend in order to change frame focus.
//
var focusThisFrame = function (request) {
  if (!request.forceFocusThisFrame) {
    if (
      DomUtils.windowIsTooSmall() ||
      (document.body && document.body.tagName.toLowerCase() == "frameset")
    ) {
      // This frame is too small to focus or it's a frameset. Cancel and tell the background page to
      // focus the next frame instead. This affects sites like Google Inbox, which have many tiny
      // iframes. See #1317.
      chrome.runtime.sendMessage({ handler: "nextFrame" });
      return;
    }
  }

  Utils.nextTick(function () {
    window.focus();
    // On Firefox, window.focus doesn't always draw focus back from a child frame (bug 554039). We
    // blur the active element if it is an iframe, which gives the window back focus as intended.
    if (document.activeElement.tagName.toLowerCase() === "iframe") {
      document.activeElement.blur();
    }
    if (request.highlight) {
      flashFrame();
    }
  });
};

// Used by focusInput command.
root.lastFocusedInput = (function () {
  // Track the most recently focused input element.
  let recentlyFocusedElement = null;
  window.addEventListener(
    "focus",
    forTrusted(function (event) {
      const DomUtils = window.DomUtils || root.DomUtils; // Workaround FF bug 1408996.
      if (DomUtils.isEditable(event.target)) {
        recentlyFocusedElement = event.target;
      }
    }),
    true,
  );
  return () => recentlyFocusedElement;
})();

// TODO(philc): Update this comment to ensure it's still fully accurate.
// Checks if Vimium should be enabled or not in this frame. As a side effect, it also informs the
// background page whether this frame has the focus, allowing the background page to track the
// active frame's URL and set the page icon.
const checkIfEnabledForUrl = async (frameIsFocused) => {
  if (frameIsFocused == null) {
    frameIsFocused = windowIsFocused();
  }
  const response = await chrome.runtime.sendMessage({
    handler: "initializeFrame",
    frameIsFocused,
    url: window.location.toString(),
  });

  // This browser info is used by other content scripts, but can only be determinted by the
  // background page.
  Utils._isFirefox = response.isFirefox;
  Utils._firefoxVersion = response.firefoxVersion;
  Utils._browserInfoLoaded = true;
  // This is the first time we learn what this frame's ID is.
  frameId = response.frameId;

  if (!normalMode) {
    installModes();
  }
  normalMode.setPassKeys(response.passKeys);
  // Hide the HUD if we're not enabled.
  if (!response.isEnabledForUrl) {
    HUD.hide(true, false);
  }
};

// When we're informed by the background page that a URL in this tab has changed, we check if we
// have the correct enabled state (but only if this frame has the focus).
var checkEnabledAfterURLChange = forTrusted(function () {
  // The URL changing feels like navigation to the user, so reset the scroller (see #3119).
  Scroller.reset();
  if (windowIsFocused()) {
    checkIfEnabledForUrl();
  }
});

// If we are in the help dialog iframe, then HelpDialog is already defined with the necessary
// functions.
if (root.HelpDialog == null) {
  root.HelpDialog = {
    helpUI: null,
    isShowing() {
      return this.helpUI && this.helpUI.showing;
    },
    abort() {
      if (this.isShowing()) {
        return this.helpUI.hide(false);
      }
    },

    toggle(request) {
      DomUtils.documentComplete(() => {
        if (!this.helpUI) {
          this.helpUI = new UIComponent(
            "pages/help_dialog.html",
            "vimiumHelpDialogFrame",
            function () {},
          );
        }
        return this.helpUI;
      });

      if ((this.helpUI != null) && this.isShowing()) {
        return this.helpUI.hide();
      } else if (this.helpUI != null) {
        return this.helpUI.activate(Object.assign(request, { name: "activate", focus: true }));
      }
    },
  };
}

initializePreDomReady();
DomUtils.documentReady(initializeOnDomReady);

Object.assign(root, {
  handlerStack,
  frameId,
  windowIsFocused,
  // These are exported for normal mode and link-hints mode.
  focusThisFrame,
  // Exported only for tests.
  installModes,
});

Object.assign(window, root);
