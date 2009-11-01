var SCROLL_STEP_SIZE = 100; // Pixels

document.addEventListener("keydown", onKeydown);
document.addEventListener("focus", onFocusCapturePhase, true);
document.addEventListener("blur", onBlurCapturePhase, true);

// Send the key to the key handler in the background page.
var keyPort = chrome.extension.connect({name: "keyDown"});
var keymap = { ESC: 27, i: 73 };
var insertMode = false;

function scrollToBottom() { window.scrollTo(0, document.body.scrollHeight); }
function scrollToTop() { window.scrollTo(0, 0); }
function scrollUp() { window.scrollBy(0, -1 * SCROLL_STEP_SIZE); }
function scrollDown() { window.scrollBy(0, SCROLL_STEP_SIZE); }
function scrollLeft() { window.scrollBy(-1 * SCROLL_STEP_SIZE, 0); }
function scrollRight() { window.scrollBy(SCROLL_STEP_SIZE, 0); }

function reload() { window.location.reload(); }

chrome.extension.onConnect.addListener(function (port, name) {
  if (port.name == "executePageCommand")
  {
    port.onMessage.addListener(function (args) {
      if (this[args.command])
      {
        for (var i = 0; i < args.count; i++) { this[args.command].call(); }
      }
    });
  }
});

/**
 * Sends everything except i & ESC to the handler in background_page. i & ESC are special because they control
 * insert mode which is local state to the page.
 *
 * Note that some keys will only register keydown events and not keystroke events, e.g. ESC.
 */
function onKeydown(event) {
  var key = event.keyCode;

  if (insertMode && key == keymap.ESC) { exitInsertMode(); }
  else if (!insertMode && key == keymap.i) { enterInsertMode(); }
  // Ignore modifier keys by themselves.
  else if (!insertMode && key > 31 && key < 127)
  {
    var keyChar = String.fromCharCode(key);
    if (event.shiftKey)
      keyPort.postMessage(keyChar.toUpperCase());
    else
      keyPort.postMessage(keyChar.toLowerCase());
  }
}

function onFocusCapturePhase(event) {
  if (event.target.tagName == "INPUT" || event.target.tagName == "TEXTAREA")
    enterInsertMode();
}

function onBlurCapturePhase(event) {
  if (event.target.tagName == "INPUT" || event.target.tagName == "TEXTAREA")
    exitInsertMode();
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
