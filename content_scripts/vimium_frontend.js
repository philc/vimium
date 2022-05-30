//
// This content script must be run prior to domReady so that we perform some operations very early.
//

const root = {};
// On Firefox, sometimes the variables assigned to window are lost (bug 1408996), so we reinstall them.
// NOTE(mrmr1993): This bug leads to catastrophic failure (ie. nothing works and errors abound).
DomUtils.documentReady(function() {
  Object.assign(window, root);
});

let isEnabledForUrl = true;
const isIncognitoMode = chrome.extension.inIncognitoContext;
let normalMode = null;

// We track whther the current window has the focus or not.
const windowIsFocused = (function() {
  let windowHasFocus = null;
  DomUtils.documentReady(() => windowHasFocus = document.hasFocus());
  window.addEventListener("focus", (forTrusted(function(event) {
    if (event.target === window)
      windowHasFocus = true;
    return true;
  })), true);
  window.addEventListener("blur", (forTrusted(function(event) {
    if (event.target === window)
      windowHasFocus = false;
    return true;
  })), true);
  return () => windowHasFocus;
})();

// This is set by Frame.registerFrameId(). A frameId of 0 indicates that this is the top frame in the tab.
let frameId = null;

// For debugging only. This writes to the Vimium log page, the URL of whichis shown on the console on the
// background page.
const bgLog = function(...args) {
  args = args.map(a => a.toString());
  Frame.postMessage("log", {message: args.join(" ")});
};

// If an input grabs the focus before the user has interacted with the page, then grab it back (if the
// grabBackFocus option is set).
class GrabBackFocus extends Mode {
  constructor() {
    super();
    let listener;
    const exitEventHandler = () => {
      return this.alwaysContinueBubbling(() => {
        this.exit();
        chrome.runtime.sendMessage({handler: "sendMessageToFrames",
                                    message: {name: "userIsInteractingWithThePage"}});
      });
    };

    super.init({
      name: "grab-back-focus",
      keydown: exitEventHandler
    });

    // True after we've grabbed back focus to the page and logged it via console.log , so web devs using Vimium
    // don't get confused.
    this.logged = false;

    this.push({
      _name: "grab-back-focus-mousedown",
      mousedown: exitEventHandler
    });

    Settings.use("grabBackFocus", grabBackFocus => {
      // It is possible that this mode exits (e.g. due to a key event) before the settings are ready -- in
      // which case we should not install this grab-back-focus watcher.
      if (this.modeIsActive) {
        if (grabBackFocus) {
          this.push({
            _name: "grab-back-focus-focus",
            focus: event => this.grabBackFocus(event.target)
          });
          // An input may already be focused. If so, grab back the focus.
          if (document.activeElement)
            this.grabBackFocus(document.activeElement);
        } else {
          this.exit();
        }
      }
    });

    // This mode is active in all frames.  A user might have begun interacting with one frame without other
    // frames detecting this.  When one GrabBackFocus mode exits, we broadcast a message to inform all
    // GrabBackFocus modes that they should exit; see #2296.
    chrome.runtime.onMessage.addListener(listener = ({name}) => {
      if (name === "userIsInteractingWithThePage") {
        chrome.runtime.onMessage.removeListener(listener);
        if (this.modeIsActive)
          this.exit();
      }
      // We will not be calling sendResponse.
      return false;
    });
  }

  grabBackFocus(element) {
    if (!DomUtils.isFocusable(element))
      return this.continueBubbling;

    if (!this.logged && (element !== document.body)) {
      this.logged = true;
      if (!window.vimiumDomTestsAreRunning)
        console.log("An auto-focusing action on this page was blocked by Vimium.");
    }
    element.blur();
    return this.suppressEvent;
  }
}

// Pages can load new content dynamically and change the displayed URL using history.pushState. Since this can
// often be indistinguishable from an actual new page load for the user, we should also re-start GrabBackFocus
// for these as well. This fixes issue #1622.
handlerStack.push({
  _name: "GrabBackFocus-pushState-monitor",
  click(event) {
    // If a focusable element is focused, the user must have clicked on it. Retain focus and bail.
    if (DomUtils.isFocusable(document.activeElement))
      return true;

    let target = event.target;

    while (target) {
      // Often, a link which triggers a content load and url change with javascript will also have the new
      // url as it's href attribute.
      if ((target.tagName === "A") &&
         (target.origin === document.location.origin) &&
         // Clicking the link will change the url of this frame.
         ((target.pathName !== document.location.pathName) ||
          (target.search !== document.location.search)) &&
         (["", "_self"].includes(target.target) ||
          ((target.target === "_parent") && (window.parent === window)) ||
          ((target.target === "_top") && (window.top === window)))) {
        return new GrabBackFocus();
      } else {
        target = target.parentElement;
      }
    }
    return true;
  }
});

const installModes = function() {
  // Install the permanent modes. The permanently-installed insert mode tracks focus/blur events, and
  // activates/deactivates itself accordingly.
  normalMode = new NormalMode();
  normalMode.init();
  // Initialize components upon which normal mode depends.
  Scroller.init();
  FindModeHistory.init();
  new InsertMode({permanent: true});
  if (isEnabledForUrl) {
    new GrabBackFocus;
  }
  // Return the normalMode object (for the tests).
  return normalMode;
};

//
// Complete initialization work that should be done prior to DOMReady.
//
const initializePreDomReady = function() {
  installListeners();
  Frame.init();
  checkIfEnabledForUrl(document.hasFocus());

  const requestHandlers = {
    focusFrame(request) {
      if (frameId === request.frameId)
        return focusThisFrame(request);
    },
    getScrollPosition(ignoredA, ignoredB, sendResponse) {
      if (frameId === 0)
        return sendResponse({scrollX: window.scrollX, scrollY: window.scrollY});
    },
    setScrollPosition,
    frameFocused() {}, // A frame has received the focus; we don't care here (UI components handle this).
    checkEnabledAfterURLChange,
    runInTopFrame({sourceFrameId, registryEntry}) {
      if (DomUtils.isTopFrame())
        return NormalModeCommands[registryEntry.command](sourceFrameId, registryEntry);
    },
    linkHintsMessage(request) { return HintCoordinator[request.messageType](request); },
    showMessage(request) { return HUD.showForDuration(request.message, 2000); },
    executeScript(request) { return DomUtils.injectUserScript(request.script); }
  };

  chrome.runtime.onMessage.addListener(function(request, sender, sendResponse) {
    request.isTrusted = true;
    // Some requests intended for the background page are delivered to the options page too; ignore them.
    if (!request.handler || !!request.name) {
      // Some request are handled elsewhere; ignore them too.
      if (request.name !== "userIsInteractingWithThePage")
        if (isEnabledForUrl || ["checkEnabledAfterURLChange", "runInTopFrame"].includes(request.name))
          requestHandlers[request.name](request, sender, sendResponse);
    }
    // Ensure that the sendResponse callback is freed.
    return false;
  });
};

// Wrapper to install event listeners.  Syntactic sugar.
const installListener = (element, event, callback) => element.addEventListener(event, forTrusted(function() {
  // TODO(philc): I think this workaround can be removed?
  if (typeof global === 'undefined' || global === null) { // See #2800.
    Object.assign(window, root);
  }
  if (isEnabledForUrl)
    return callback.apply(this, arguments);
  else
    return true;
}), true);

//
// Installing or uninstalling listeners is error prone. Instead we elect to check isEnabledForUrl each time so
// we know whether the listener should run or not.
// Run this as early as possible, so the page can't register any event handlers before us.
// Note: We install the listeners even if Vimium is disabled. See comment in commit
// 6446cf04c7b44c3d419dc450a73b60bcaf5cdf02.
//
var installListeners = Utils.makeIdempotent(function() {
  // Key event handlers fire on window before they do on document. Prefer window for key events so the page
  // can't set handlers to grab the keys before us.
  for (let type of ["keydown", "keypress", "keyup", "click", "focus", "blur", "mousedown", "scroll"]) {
    // TODO(philc): Can we remove this extra closure?
    ((type => installListener(window, type, event => handlerStack.bubbleEvent(type, event))))(type);
  }
  return installListener(document, "DOMActivate", event => handlerStack.bubbleEvent('DOMActivate', event));
});

// Whenever we get the focus:
// - Tell the background page this frame's URL.
// - Check if we should be enabled.
const onFocus = forTrusted(function(event) {
  if (event.target === window) {
    chrome.runtime.sendMessage({handler: "frameFocused"});
    checkIfEnabledForUrl(true);
  }
});

// We install these listeners directly (that is, we don't use installListener) because we still need to receive
// events when Vimium is not enabled.
window.addEventListener("focus", onFocus, true);
window.addEventListener("hashchange", checkEnabledAfterURLChange, true);

const initializeOnDomReady = () => // Tell the background page we're in the domReady state.
Frame.postMessage("domReady");

var Frame = {
  port: null,
  listeners: {},

  addEventListener(handler, callback) {
    this.listeners[handler] = callback;
  },

  postMessage(handler, request) {
    if (request == null)
      request = {};
    this.port.postMessage(Object.assign(request, {handler}));
  },

  linkHintsMessage(request) {
    return HintCoordinator[request.messageType](request);
  },

  registerFrameId(request) {
    frameId = (root.frameId = (window.frameId = request.chromeFrameId));
    if (Utils.isFirefox()) {
      Utils.firefoxVersion = () => request.firefoxVersion
    }
    // We register a frame immediately only if it is focused or its window isn't tiny.  We register tiny
    // frames later, when necessary.  This affects focusFrame() and link hints.
    if (windowIsFocused() || !DomUtils.windowIsTooSmall()) {
      return Frame.postMessage("registerFrame");
    } else {
      let focusHandler, resizeHandler;
      const postRegisterFrame = function() {
        window.removeEventListener("focus", focusHandler, true);
        window.removeEventListener("resize", resizeHandler, true);
        return Frame.postMessage("registerFrame");
      };
      window.addEventListener("focus", (focusHandler = forTrusted(function(event) {
        if (event.target === window)
          postRegisterFrame();
      })), true);
      return window.addEventListener("resize", (resizeHandler = forTrusted(function(event) {
        if (!DomUtils.windowIsTooSmall())
          postRegisterFrame();
      })), true);
    }
  },

  init() {
    let disconnect;
    this.port = chrome.runtime.connect({name: "frames"});

    this.port.onMessage.addListener(request => {
      if (typeof global === 'undefined' || global === null) { // See #2800 and #2831.
        Object.assign(window, root);
      }
      const handler = this.listeners[request.handler] || this[request.handler];
      handler(request);
      // return (this.listeners[request.handler] != null ? this.listeners[request.handler] : this[request.handler])(request);
    });

    // We disable the content scripts when we lose contact with the background page, or on unload.
    this.port.onDisconnect.addListener(disconnect = Utils.makeIdempotent(() => this.disconnect()));
    return window.addEventListener("unload", (forTrusted(function(event) {
      if (event.target === window)
        return disconnect();
    })), true);
  },

  disconnect() {
    try { this.postMessage("unregisterFrame"); } catch (error) {}
    try { this.port.disconnect(); } catch (error1) {}
    this.postMessage = this.disconnect = function() {};
    this.port = null;
    this.listeners = {};
    HintCoordinator.exit({isSuccess: false});
    handlerStack.reset();
    isEnabledForUrl = false;
    window.removeEventListener("focus", onFocus, true);
    window.removeEventListener("hashchange", checkEnabledAfterURLChange, true);
  }
};

var setScrollPosition = ({ scrollX, scrollY }) => DomUtils.documentReady(function() {
  if (DomUtils.isTopFrame()) {
    Utils.nextTick(function() {
      window.focus();
      document.body.focus();
      if ((scrollX > 0) || (scrollY > 0)) {
        Marks.setPreviousPosition();
        window.scrollTo(scrollX, scrollY);
      }
    });
  }
});

const flashFrame = (function() {
  let highlightedFrameElement = null;

  return function() {
    if (highlightedFrameElement == null) {
      // TODO(philc): Make this a regular if body, not a closure.
      highlightedFrameElement = (function() {
        // Create a shadow DOM wrapping the frame so the page's styles don't interfere with ours.

        highlightedFrameElement = DomUtils.createElement("div");
        // Firefox doesn't support createShadowRoot, so guard against its non-existance.
        // https://hacks.mozilla.org/2018/10/firefox-63-tricks-and-treats/ says
        // Firefox 63 has enabled Shadow DOM v1 by default
        const _shadowDOM =
              highlightedFrameElement.attachShadow ?
              highlightedFrameElement.attachShadow({mode: "open"}) :
              highlightedFrameElement;

        // Inject stylesheet.
        const _styleSheet = DomUtils.createElement("style");
        _styleSheet.innerHTML = `@import url(\"${chrome.runtime.getURL("content_scripts/vimium.css")}\");`;
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
var focusThisFrame = function(request) {
  if (!request.forceFocusThisFrame) {
    if (DomUtils.windowIsTooSmall() || (document.body && document.body.tagName.toLowerCase() == "frameset")) {
      // This frame is too small to focus or it's a frameset. Cancel and tell the background page to focus the
      // next frame instead.  This affects sites like Google Inbox, which have many tiny iframes. See #1317.
      chrome.runtime.sendMessage({handler: "nextFrame"});
      return;
    }
  }

  Utils.nextTick(function() {
    window.focus();
    // On Firefox, window.focus doesn't always draw focus back from a child frame (bug 554039).
    // We blur the active element if it is an iframe, which gives the window back focus as intended.
    if (document.activeElement.tagName.toLowerCase() === "iframe")
      document.activeElement.blur();
    if (request.highlight)
      flashFrame();
  });
};

// Used by focusInput command.
root.lastFocusedInput = (function() {
  // Track the most recently focused input element.
  let recentlyFocusedElement = null;
  window.addEventListener("focus",
    forTrusted(function(event) {
      const DomUtils = window.DomUtils || root.DomUtils; // Workaround FF bug 1408996.
      if (DomUtils.isEditable(event.target))
        recentlyFocusedElement = event.target;
    })
  , true);
  return () => recentlyFocusedElement;
})();

// Checks if Vimium should be enabled or not in this frame.  As a side effect, it also informs the background
// page whether this frame has the focus, allowing the background page to track the active frame's URL and set
// the page icon.
var checkIfEnabledForUrl = (function() {
  Frame.addEventListener("isEnabledForUrl", function(response) {
    let frameIsFocused, isFirefox, passKeys;
    ({isEnabledForUrl, passKeys, frameIsFocused, isFirefox} = response);
    Utils.isFirefox = () => isFirefox;
    if (!normalMode)
      installModes();
    normalMode.setPassKeys(passKeys);
    // Hide the HUD if we're not enabled.
    if (!isEnabledForUrl)
      return HUD.hide(true, false);
  });

  return function(frameIsFocused) {
    if (frameIsFocused == null)
      frameIsFocused = windowIsFocused();
    return Frame.postMessage("isEnabledForUrl", {frameIsFocused, url: window.location.toString()});
  };
})();

// When we're informed by the background page that a URL in this tab has changed, we check if we have the
// correct enabled state (but only if this frame has the focus).
var checkEnabledAfterURLChange = forTrusted(function() {
  Scroller.reset(); // The URL changing feels like navigation to the user, so reset the scroller (see #3119).
  if (windowIsFocused())
    checkIfEnabledForUrl();
});

// If we are in the help dialog iframe, then HelpDialog is already defined with the necessary functions.
if (root.HelpDialog == null) {
  root.HelpDialog = {
    helpUI: null,
    isShowing() {
      return this.helpUI && this.helpUI.showing;
    },
    abort() {
      if (this.isShowing())
        return this.helpUI.hide(false);
    },

    toggle(request) {
      DomUtils.documentComplete(() => {
        if (!this.helpUI)
          this.helpUI = new UIComponent("pages/help_dialog.html", "vimiumHelpDialogFrame", function() {});
        return this.helpUI;
      });

      if ((this.helpUI != null) && this.isShowing())
        return this.helpUI.hide();
      else if (this.helpUI != null)
        return this.helpUI.activate(Object.assign(request, {name: "activate", focus: true}));
    }
  };
}

initializePreDomReady();
DomUtils.documentReady(initializeOnDomReady);

Object.assign(root, {
  handlerStack,
  frameId,
  Frame,
  windowIsFocused,
  bgLog,
  // These are exported for normal mode and link-hints mode.
  focusThisFrame,
  // Exported only for tests.
  installModes
});

Object.assign(window, root);
