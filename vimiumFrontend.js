/*
 * This content script takes input from its webpage and executes commands locally on behalf of the background
 * page. It must be run prior to domReady so that we perform some operations very early, like setting
 * the page's zoom level. We tell the background page that we're in domReady and ready to accept normal
 * commands by connectiong to a port named "domReady".
 */
var settings = {};
var settingsToLoad = ["scrollStepSize"];

var getCurrentUrlHandlers = []; // function(url)

var keyCodes = { ESC: 27, backspace: 8, deleteKey: 46, enter: 13 };
var insertMode = false;
var findMode = false;
var findModeQuery = "";
var keyPort;
var settingPort;
var saveZoomLevelPort;

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

  document.addEventListener("keydown", onKeydown);
  document.addEventListener("focus", onFocusCapturePhase, true);
  document.addEventListener("blur", onBlurCapturePhase, true);

  var getZoomLevelPort = chrome.extension.connect({ name: "getZoomLevel" });
  getZoomLevelPort.postMessage({ domain: window.location.host });

  // Send the key to the key handler in the background page.
  keyPort = chrome.extension.connect({name: "keyDown"});

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
        setPageZoomLevel(currentZoomLevel);
      });
    } else if (port.name == "returnSetting") {
      port.onMessage.addListener(setSetting);
    }
  });
}

/*
 * Initialization tasks that must wait for the document to be ready.
 */
function initializeOnDomReady() {
  // Enter insert mode automatically if there's already a text box focused.
  var focusNode = window.getSelection().focusNode;
  var focusOffset = window.getSelection().focusOffset;
  if (focusNode && focusOffset && focusNode.children.length > focusOffset &&
      isInputOrText(focusNode.children[focusOffset])) { enterInsertMode(); }
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
function setPageZoomLevel(zoomLevel) { document.documentElement.style.zoom = zoomLevel + "%"; }

function zoomIn() {
  setPageZoomLevel(currentZoomLevel += 20);
  saveZoomLevel(window.location.host, currentZoomLevel);
}

function zoomOut() {
  setPageZoomLevel(currentZoomLevel -= 20);
  saveZoomLevel(window.location.host, currentZoomLevel);
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
  if (event.keyCode > 31 && event.keyCode < 127) {
    keyChar = String.fromCharCode(event.keyCode).toLowerCase();
    if (event.shiftKey)
      keyChar = keyChar.toUpperCase();
    if (event.ctrlKey)
      keyChar = "<c-" + keyChar + ">";
  }

  // NOTE(ilya): Not really sure why yet but / yields 191 (¿) on my mac.
  if (event.keyCode == 191) { keyChar = "/"; }

  if (insertMode && event.keyCode == keyCodes.ESC)
  {
    // Remove focus so the user can't just get himself back into insert mode by typing in the same input box.
    if (isInputOrText(event.srcElement)) { event.srcElement.blur(); }
    exitInsertMode();
  }
  else if (findMode)
  {
    if (event.keyCode == keyCodes.ESC)
      exitFindMode();
    else if (keyChar)
      handleKeyCharForFindMode(keyChar);
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
  if (isInputOrText(event.target))
    enterInsertMode();
}

function onBlurCapturePhase(event) {
  if (isInputOrText(event.target))
    exitInsertMode();
}

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
  performFind();
}

function handleDeleteForFindMode() {
  if (findModeQuery.length == 0)
    exitFindMode();
  else
  {
    findModeQuery = findModeQuery.substring(0, findModeQuery.length - 1);
    showFindModeHUDForQuery();
  }

  performFind();
}

function handleEnterForFindMode() {
  exitFindMode();
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
    newQuery = newQuery + query[i] + "<span style=\"font-size: 0px;\"> </span>";

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

HUD = {
  show:function(text) {
    HUD.displayElement().innerHTML = text;
    HUD.displayElement().style.display = "";
  },

  /*
   * Retrieves the HUD HTML element, creating it if necessary.
   */
  displayElement: function() {
    if (!HUD._displayElement) {
      var element = document.createElement("div");
      element.innerHTML = "howdy";
      element.style.position = "fixed";
      element.style.bottom = "0px";
      element.style.right = "20px";
      element.style.backgroundColor = " #e5e5e5";
      element.style.maxWidth = "400px";
      element.style.fontSize = "11px";
      element.style.padding = "3px";
      element.style.border = "1px solid #cccccc";
      element.style.borderBottomWidth = "0px";
      // element.style.fontFamily = "monospace";
      document.body.appendChild(element);
      HUD._displayElement = element
    }
    return HUD._displayElement
  },

  hide: function() {
    HUD.displayElement().style.display = "none";
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
