var SCROLL_STEP_SIZE = 60; // Pixels
var getCurrentUrlHandlers = []; // function (url)

var keyCodes = { ESC: 27 };
var insertMode = false;
var keyPort;

// TODO(philc): This should be pulled from the extension's storage when the page loads.
var currentZoomLevel = 100;

function initializeFrontend() {
  document.addEventListener("keydown", onKeydown);
  document.addEventListener("focus", onFocusCapturePhase, true);
  document.addEventListener("blur", onBlurCapturePhase, true);

  // Send the key to the key handler in the background page.
  keyPort = chrome.extension.connect({name: "keyDown"});

  chrome.extension.onConnect.addListener(function (port, name) {
    if (port.name == "executePageCommand") {
      port.onMessage.addListener(function (args) {
        if (this[args.command])
        {
          for (var i = 0; i < args.count; i++) { this[args.command].call(); }
        }
      });
    }
    else if (port.name == "getScrollPosition") {
      port.onMessage.addListener(function (args) {
        var scrollPort = chrome.extension.connect({ name: "returnScrollPosition" });
        scrollPort.postMessage({
          scrollX: window.scrollX,
          scrollY: window.scrollY,
          currentTab: args.currentTab
        });
      });
    } else if (port.name == "setScrollPosition") {
      port.onMessage.addListener(function (args) {
        if (args.scrollX > 0 || args.scrollY > 0) { window.scrollBy(args.scrollX, args.scrollY); }
      });
    } else if (port.name == "returnCurrentTabUrl") {
      port.onMessage.addListener(function (args) {
        if (getCurrentUrlHandlers.length > 0) { getCurrentUrlHandlers.pop()(args.url); }
      });
    }
  });

  // Enter insert mode automatically if there's already a text box focused.
  var focusNode = window.getSelection().focusNode;
  var focusOffset = window.getSelection().focusOffset;
  if (focusNode && focusOffset &&
      isInputOrText(focusNode.children[focusOffset])) { enterInsertMode(); }
};

/*
 * Zoom in increments of 20%; this matches chrome's CMD+ and CMD- keystrokes.
 */
function zoomIn() { document.body.style.zoom = (currentZoomLevel += 20) + "%"; }
function zoomOut() { document.body.style.zoom = (currentZoomLevel -= 20) + "%"; }

function scrollToBottom() { window.scrollTo(0, document.body.scrollHeight); }
function scrollToTop() { window.scrollTo(0, 0); }
function scrollUp() { window.scrollBy(0, -1 * SCROLL_STEP_SIZE); }
function scrollDown() { window.scrollBy(0, SCROLL_STEP_SIZE); }
function scrollPageUp() { window.scrollBy(0, -6 * SCROLL_STEP_SIZE); }
function scrollPageDown() { window.scrollBy(0, 6 * SCROLL_STEP_SIZE); }
function scrollLeft() { window.scrollBy(-1 * SCROLL_STEP_SIZE, 0); }
function scrollRight() { window.scrollBy(SCROLL_STEP_SIZE, 0); }

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

  // Ignore modifier keys by themselves.
  if (event.keyCode > 31 && event.keyCode < 127) {
    keyChar = String.fromCharCode(event.keyCode).toLowerCase();
    if (event.shiftKey)
      keyChar = keyChar.toUpperCase();
    if (event.ctrlKey)
      keyChar = "<c-" + keyChar + ">";
  }

  if (insertMode && event.keyCode == keyCodes.ESC)
  {
    // Remove focus so the user can't just get himself back into insert mode by typing in the same input box.
    if (isInputOrText(event.srcElement)) { event.srcElement.blur(); }
    exitInsertMode();
  }
  else if (!insertMode && keyChar)
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
  return (target.tagName == "INPUT" || target.tagName == "TEXTAREA");
}

function enterInsertMode() {
  insertMode = true;
  HUD.show("Insert mode");
}

function exitInsertMode() {
  insertMode = false;
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
      element.style.left = "10px";
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
if (!isIframe)
  initializeFrontend();
