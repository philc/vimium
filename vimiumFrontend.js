/*
 * This content script takes input from its webpage and executes commands locally on behalf of the background
 * page. It must be run prior to domReady so that we perform some operations very early, like setting
 * the page's zoom level. We tell the background page that we're in domReady and ready to accept normal
 * commands by connectiong to a port named "domReady".
 */
var settings = {};
var settingsToLoad = ["scrollStepSize"];

var getCurrentUrlHandlers = []; // function(url)

var keyCodes = { ESC: 27, backspace: 8, deleteKey: 46, enter: 13, space: 32 };
var insertMode = false;
var findMode = false;
var findModeQuery = "";
var keyPort;
var settingPort;
var saveZoomLevelPort;
// Users can disable Vimium on URL patterns via the settings page.
var isEnabledForUrl = true;

// TODO(philc): This should be pulled from the extension's storage when the page loads.
var currentZoomLevel = 100;

function getSetting(key) {
  if (!settingPort)
    settingPort = chrome.extension.connect({ name: "getSetting" });
  settingPort.postMessage({ key: key });
}

function setSetting(args) { settings[args.key] = args.value; }

/*
 * Complete initialization work that sould be done prior to DOMReady, like setting the page's zoom level.
 */
function initializePreDomReady() {
  for (var i in settingsToLoad) { getSetting(settingsToLoad[i]); }

  var isEnabledForUrlPort = chrome.extension.connect({ name: "isEnabledForUrl" });
  isEnabledForUrlPort.postMessage({ url: window.location.toString() });

  var getZoomLevelPort = chrome.extension.connect({ name: "getZoomLevel" });
  getZoomLevelPort.postMessage({ domain: window.location.host });

  // Send the key to the key handler in the background page.
  keyPort = chrome.extension.connect({ name: "keyDown" });

  chrome.extension.onConnect.addListener(function(port, name) {
    if (port.name == "executePageCommand") {
      port.onMessage.addListener(function(args) {
        if (this[args.command]) {
          for (var i = 0; i < args.count; i++) { this[args.command].call(); }
        }
      });
    }
    else if (port.name == "getScrollPosition") {
      port.onMessage.addListener(function(args) {
        var scrollPort = chrome.extension.connect({ name: "returnScrollPosition" });
        scrollPort.postMessage({
          scrollX: window.scrollX,
          scrollY: window.scrollY,
          currentTab: args.currentTab
        });
      });
    } else if (port.name == "setScrollPosition") {
      port.onMessage.addListener(function(args) {
        if (args.scrollX > 0 || args.scrollY > 0) { window.scrollBy(args.scrollX, args.scrollY); }
      });
    } else if (port.name == "returnCurrentTabUrl") {
      port.onMessage.addListener(function(args) {
        if (getCurrentUrlHandlers.length > 0) { getCurrentUrlHandlers.pop()(args.url); }
      });
    } else if (port.name == "returnZoomLevel") {
      port.onMessage.addListener(function(args) {
        currentZoomLevel = args.zoomLevel;
        if (isEnabledForUrl)
          setPageZoomLevel(currentZoomLevel);
      });
    } else if (port.name == "returnIsEnabledForUrl") {
      port.onMessage.addListener(function(args) {
        isEnabledForUrl = args.isEnabledForUrl;
        if (isEnabledForUrl)
          initializeWhenEnabled();
        else if (HUD.isReady())
          // Quickly hide any HUD we might already be showing, e.g. if we entered insertMode on page load.
          HUD.hide();
      });
    } else if (port.name == "returnSetting") {
      port.onMessage.addListener(setSetting);
    }
  });
}

/*
 * This is called once the background page has told us that Vimium should be enabled for the current URL.
 */
function initializeWhenEnabled() {
  document.addEventListener("keydown", onKeydown);
  document.addEventListener("focus", onFocusCapturePhase, true);
  document.addEventListener("blur", onBlurCapturePhase, true);
}

/*
 * Initialization tasks that must wait for the document to be ready.
 */
function initializeOnDomReady() {
  if (isEnabledForUrl) {
    // Enter insert mode automatically if there's already a text box focused.
    var focusNode = window.getSelection().focusNode;
    var focusOffset = window.getSelection().focusOffset;
    if (focusNode && focusOffset && focusNode.children.length > focusOffset &&
        isInputOrText(focusNode.children[focusOffset]))
      enterInsertMode();
  }
  // Tell the background page we're in the dom ready state.
  chrome.extension.connect({ name: "domReady" });
};

/*
 * Asks the background page to persist the zoom level for the given domain to localStorage.
 */
function saveZoomLevel(domain, zoomLevel) {
  if (!saveZoomLevelPort)
    saveZoomLevelPort = chrome.extension.connect({ name: "saveZoomLevel" });
  saveZoomLevelPort.postMessage({ domain: domain, zoomLevel: zoomLevel });
}

/*
 * Zoom in increments of 20%; this matches chrome's CMD+ and CMD- keystrokes.
 * Set the zoom style on documentElement because document.body does not exist pre-page load.
 */
function setPageZoomLevel(zoomLevel, showUINotification) {
  document.documentElement.style.zoom = zoomLevel + "%";
  if (document.body)
    HUD.updatePageZoomLevel(zoomLevel);
  if (showUINotification)
    HUD.showForDuration("Zoom: " + currentZoomLevel + "%", 1000);
}

function zoomIn() {
  setPageZoomLevel(currentZoomLevel += 20, true);
  saveZoomLevel(window.location.host, currentZoomLevel);
}

function zoomOut() {
  setPageZoomLevel(currentZoomLevel -= 20, true);
  saveZoomLevel(window.location.host, currentZoomLevel, showUINotification);
}

function scrollToBottom() { window.scrollTo(0, document.body.scrollHeight); }
function scrollToTop() { window.scrollTo(0, 0); }
function scrollUp() { window.scrollBy(0, -1 * settings["scrollStepSize"]); }
function scrollDown() { window.scrollBy(0, settings["scrollStepSize"]); }
function scrollPageUp() { window.scrollBy(0, -6 * settings["scrollStepSize"]); }
function scrollPageDown() { window.scrollBy(0, 6 * settings["scrollStepSize"]); }
function scrollLeft() { window.scrollBy(-1 * settings["scrollStepSize"], 0); }
function scrollRight() { window.scrollBy(settings["scrollStepSize"], 0); }

function reload() { window.location.reload(); }
function goBack() { history.back(); }
function goForward() { history.forward(); }

function toggleViewSource() {
  getCurrentUrlHandlers.push(toggleViewSourceCallback);

  var getCurrentUrlPort = chrome.extension.connect({ name: "getCurrentTabUrl" });
  getCurrentUrlPort.postMessage({});
}

function toggleViewSourceCallback(url) {
  if (url.substr(0, 12) == "view-source:")
  {
    window.location.href = url.substr(12, url.length - 12);
  }
  else { window.location.href = "view-source:" + url; }
}

/**
 * Sends everything except i & ESC to the handler in background_page. i & ESC are special because they control
 * insert mode which is local state to the page. The key will be are either a single ascii letter or a
 * key-modifier pair, e.g. <c-a> for control a.
 *
 * Note that some keys will only register keydown events and not keystroke events, e.g. ESC.
 */
function onKeydown(event) {
  var keyChar = "";

  if (linkHintsModeActivated)
    return;

  // Ignore modifier keys by themselves.
  if (event.keyCode > 31) {
    unicodeKeyInHex = "0x" + event.keyIdentifier.substring(2);
    keyChar = String.fromCharCode(parseInt(unicodeKeyInHex)).toLowerCase();

    if (event.shiftKey)
      keyChar = keyChar.toUpperCase();
    if (event.ctrlKey)
      keyChar = "<c-" + keyChar + ">";
  }

  if (insertMode && event.keyCode == keyCodes.ESC)
  {
    // Note that we can't programmatically blur out of Flash embeds from Javascript.
    if (event.srcElement.tagName != "EMBED") {
      // Remove focus so the user can't just get himself back into insert mode by typing in the same input box.
      if (isInputOrText(event.srcElement)) { event.srcElement.blur(); }
      exitInsertMode();
    }
  }
  else if (findMode)
  {
    if (event.keyCode == keyCodes.ESC)
      exitFindMode();
    else if (keyChar)
    {
      handleKeyCharForFindMode(keyChar);

      // Don't let the space scroll us if we're searching.
      if (event.keyCode == keyCodes.space)
        event.preventDefault();
    }
    // Don't let backspace take us back in history.
    else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey)
    {
      handleDeleteForFindMode();
      event.preventDefault();
    }
    else if (event.keyCode == keyCodes.enter)
      handleEnterForFindMode();
  }
  else if (!insertMode && !findMode && keyChar)
    keyPort.postMessage(keyChar);
}

function onFocusCapturePhase(event) {
  if (isFocusable(event.target))
    enterInsertMode();
}

function onBlurCapturePhase(event) {
  if (isFocusable(event.target))
    exitInsertMode();
}

/*
 * Returns true if the element is focusable. This includes embeds like Flash, which steal the keybaord focus.
 */
function isFocusable(element) { return isInputOrText(element) || element.tagName == "EMBED"; }

function isInputOrText(target) {
  return ((target.tagName == "INPUT" && (target.type == "text" || target.type == "password")) ||
          target.tagName == "TEXTAREA");
}

function enterInsertMode() {
  insertMode = true;
  HUD.show("Insert mode");
}

function exitInsertMode() {
  insertMode = false;
  HUD.hide();
}

function handleKeyCharForFindMode(keyChar) {
  findModeQuery = findModeQuery + keyChar;
  showFindModeHUDForQuery();
  performFindInPlace();
}

function handleDeleteForFindMode() {
  if (findModeQuery.length == 0)
    exitFindMode();
  else
  {
    findModeQuery = findModeQuery.substring(0, findModeQuery.length - 1);
    showFindModeHUDForQuery();
  }

  performFindInPlace();
}

function handleEnterForFindMode() {
  exitFindMode();
  performFindInPlace();
}

function performFindInPlace() {
  var cachedScrollX = window.scrollX;
  var cachedScrollY = window.scrollY;

  // Search backwards first to "free up" the current word as eligible for the real forward search. This allows
  // us to search in place without jumping around between matches as the query grows.
  window.find(findModeQuery, false, true, true, false, true, false);

  // We need to restore the scroll position because we might've lost the right position by searching
  // backwards.
  window.scrollTo(cachedScrollX, cachedScrollY);

  performFind();
}

function performFind() {
  window.find(findModeQuery, false, false, true, false, true, false);
}

function performBackwardsFind() {
  window.find(findModeQuery, false, true, true, false, true, false);
}

function showFindModeHUDForQuery() {
  HUD.show("/" + insertSpaces(findModeQuery));
}

/*
 * We need this so that the find mode HUD doesn't match its own searches.
 */
function insertSpaces(query) {
  var newQuery = "";

  for (var i = 0; i < query.length; i++)
  {
    if (query[i] == " " || (i + 1 < query.length && query[i + 1] == " "))
      newQuery = newQuery + query[i];
    else
      newQuery = newQuery + query[i] + "<span style=\"font-size: 0px;\"> </span>";
  }

  return newQuery;
}

function enterFindMode() {
  findModeQuery = "";
  findMode = true;
  HUD.show("/");
}

function exitFindMode() {
  findMode = false;
  HUD.hide();
}

/*
 * A heads-up-display for showing Vimium page operations.
 * Note: you cannot interact with the HUD until document.body is available.
 */
HUD = {
  showForDuration: function(text, duration) {
    HUD.show(text);
    HUD._showForDurationTimerId = setTimeout(function() { HUD.hide(); }, duration);
  },

  show: function(text) {
    clearTimeout(HUD._showForDurationTimerId);
    HUD.displayElement().innerHTML = text;
    if (HUD.displayElement().style.opacity == 0) {
      Tween.fade(HUD.displayElement(), 1.0, 150);
      HUD.displayElement().style.display = "";
    }
  },

  updatePageZoomLevel: function(pageZoomLevel) {
    // Since the chrome HUD does not scale with the page's zoom level, neither will this HUD.
    HUD.displayElement().style.zoom = (100.0 / pageZoomLevel) * 100 + "%";
  },

  /*
   * Retrieves the HUD HTML element, creating it if necessary.
   */
  displayElement: function() {
    if (!HUD._displayElement) {
      // This is styled to precisely mimick the chrome HUD. Use the "has_popup_and_link_hud.html" test harness
      // to tweak these styles to match Chrome's. One limitation of our HUD display is that it doesn't sit
      // on top of horizontal scrollbars like Chrome's HUD does.
      var element = document.createElement("div");
      element.style.position = "fixed";
      element.style.bottom = "0px";
      // Keep this far enough to the right so that it doesn't collide with the "popups blocked" chrome HUD.
      element.style.right = "150px";
      element.style.height = "13px";
      element.style.maxWidth = "400px";
      element.style.minWidth = "150px";
      element.style.backgroundColor = "#ebebeb";
      element.style.fontSize = "11px";
      element.style.padding = "3px 3px 2px 3px";
      element.style.border = "1px solid #b3b3b3";
      element.style.borderRadius = "4px 4px 0 0";
      element.style.fontFamily = "Lucida Grande";
      element.style.zIndex = 99999999999;
      element.style.textShadow = "0px 1px 2px #FFF";
      element.style.lineHeight = "1.0";
      element.style.opacity = 0;

      document.body.appendChild(element);
      HUD._displayElement = element
      HUD.updatePageZoomLevel(currentZoomLevel);
    }
    return HUD._displayElement;
  },

  hide: function() {
    Tween.fade(HUD.displayElement(), 0, 150, function() { HUD.displayElement().display == "none"; });
  },

  isReady: function() { return document.body != null; }
};

Tween = {
  /*
   * Fades an element's alpha. Returns a timer ID which can be used to stop the tween via clearInterval.
   */
  fade: function(element, toAlpha, duration, onComplete) {
    var state = {};
    state.duration = duration;
    state.startTime = (new Date()).getTime();
    state.from = parseInt(element.style.opacity) || 0;
    state.to = toAlpha;
    state.onUpdate = function(value) {
      element.style.opacity = value;
      if (value == state.to && onComplete)
        onComplete();
    };
    state.timerId = setInterval(function() { Tween.performTweenStep(state); }, 50);
    return state.timerId;
  },

  performTweenStep: function(state) {
    var elapsed = (new Date()).getTime() - state.startTime;
    if (elapsed >= state.duration) {
      clearInterval(state.timerId);
      state.onUpdate(state.to)
    } else {
      var value = (elapsed / state.duration)  * (state.to - state.from) + state.from;
      state.onUpdate(value);
    }
  }
};

// Prevent our content script from being run on iframes -- only allow it to run on the top level DOM "window".
// TODO(philc): We don't want to process multiple keyhandlers etc. when embedded on a page containing IFrames.
// This should be revisited, because sometimes we *do* want to listen inside of the currently focused iframe.
var isIframe = (window.self != window.parent);
if (!isIframe) {
  initializePreDomReady();
  window.addEventListener("DOMContentLoaded", initializeOnDomReady);
}
