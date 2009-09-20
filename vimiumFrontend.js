document.addEventListener("keydown", onKeydown);
document.addEventListener("focus", onFocusCapturePhase, true);
document.addEventListener("blur", onBlurCapturePhase, true);

// Used to communicate with the background page and send it native browser commands that
// we want executed.
var commandPort = chrome.extension.connect({name: "nativeCommand"});

var keymap = {
  ESC: 27,
  a: 65,
  d: 68,
  i: 73,
  t: 84
};

var insertMode = false;

/*
 * Executes commands based on the keystroke.
 * Note that some keys will only register keydown events and not keystroke events, e.g. ESC.
 */
function onKeydown(event) { 
  var key = event.keyCode;
  console.log(key);

  if (insertMode) {
    if (key == keymap.ESC)
      exitInsertMode();
    return;
  }

  var request;
  if (key == keymap.d)
    request = { command: "tabs.remove" };
  else if (key == keymap.t)
    request = { command: "tabs.create" };
  else if (key == keymap.i)
    enterInsertMode();
  else
    return;

  event.preventDefault();
  commandPort.postMessage(request);
  console.log(event);
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
