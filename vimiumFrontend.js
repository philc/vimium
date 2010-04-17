/*
 * This content script takes input from its webpage and executes commands locally on behalf of the background
 * page. It must be run prior to domReady so that we perform some operations very early, like setting
 * the page's zoom level. We tell the background page that we're in domReady and ready to accept normal
 * commands by connectiong to a port named "domReady".
 */
var settings = {};
var settingsToLoad = ["scrollStepSize", "linkHintCharacters"];

var getCurrentUrlHandlers = []; // function(url)

var insertMode = false;
var findMode = false;
var findModeQuery = "";
var findModeQueryHasResults = false;
var isShowingHelpDialog = false;
var keyPort;
var settingPort;
var saveZoomLevelPort;
// Users can disable Vimium on URL patterns via the settings page.
var isEnabledForUrl = true;
// The user's operating system.
var currentCompletionKeys;
var linkHintCss;

// TODO(philc): This should be pulled from the extension's storage when the page loads.
var currentZoomLevel = 100;

var hasModifiersRegex = /^<([amc]-)+.>/;

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

  chrome.extension.sendRequest({handler: "getLinkHintCss"}, function (response) {
    linkHintCss = response.linkHintCss;
  });

  refreshCompletionKeys();

  // Send the key to the key handler in the background page.
  keyPort = chrome.extension.connect({ name: "keyDown" });

  chrome.extension.onRequest.addListener(function(request, sender, sendResponse) {
    if (request.name == "hideUpgradeNotification")
      HUD.hideUpgradeNotification();
    else if (request.name == "showUpgradeNotification" && isEnabledForUrl)
      HUD.showUpgradeNotification(request.version);
    else if (request.name == "showHelpDialog")
      if (isShowingHelpDialog)
        hideHelpDialog();
      else
        showHelpDialog(request.dialogHtml);
    else if (request.name == "refreshCompletionKeys")
      refreshCompletionKeys(request.completionKeys);
    sendResponse({}); // Free up the resources used by this open connection.
  });

  chrome.extension.onConnect.addListener(function(port, name) {
    if (port.name == "executePageCommand") {
      port.onMessage.addListener(function(args) {
        if (this[args.command]) {
          for (var i = 0; i < args.count; i++) { this[args.command].call(); }
        }

        refreshCompletionKeys(args.completionKeys);
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
    } else if (port.name == "refreshCompletionKeys") {
      port.onMessage.addListener(function (args) {
        refreshCompletionKeys(args.completionKeys);
      });
    }
  });
}

/*
 * This is called once the background page has told us that Vimium should be enabled for the current URL.
 */
function initializeWhenEnabled() {
  document.addEventListener("keydown", onKeydown, true);
  document.addEventListener("focus", onFocusCapturePhase, true);
  document.addEventListener("blur", onBlurCapturePhase, true);
  enterInsertModeIfElementIsFocused();
}

/*
 * Initialization tasks that must wait for the document to be ready.
 */
function initializeOnDomReady() {
  if (isEnabledForUrl)
    enterInsertModeIfElementIsFocused();

  // Tell the background page we're in the dom ready state.
  chrome.extension.connect({ name: "domReady" });
};

/*
 * Checks the currently focused element of the document and will enter insert mode if that element is focusable.
 */
function enterInsertModeIfElementIsFocused() {
  // Enter insert mode automatically if there's already a text box focused.
  if (document.activeElement && isEditable(document.activeElement))
    enterInsertMode();
}

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
  saveZoomLevel(window.location.host, currentZoomLevel);
}

function scrollToBottom() { window.scrollTo(0, document.body.scrollHeight); }
function scrollToTop() { window.scrollTo(0, 0); }
function scrollUp() { window.scrollBy(0, -1 * settings["scrollStepSize"]); }
function scrollDown() { window.scrollBy(0, settings["scrollStepSize"]); }
function scrollPageUp() { window.scrollBy(0, -1 * window.innerHeight / 2); }
function scrollPageDown() { window.scrollBy(0, window.innerHeight / 2); }
function scrollFullPageUp() { window.scrollBy(0, -window.innerHeight); }
function scrollFullPageDown() { window.scrollBy(0, window.innerHeight); }
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

function copyCurrentUrl() {
  getCurrentUrlHandlers.push(function (url) { Clipboard.copy(url); });

  // TODO(ilya): Convert to sendRequest.
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
    keyChar = getKeyChar(event);

    // Enter insert mode when the user enables the native find interface.
    if (keyChar == "f" && !event.shiftKey && isPrimaryModifierKey(event))
    {
      enterInsertMode();
      return;
    }

    if (keyChar != "") // Again, ignore just modifiers. Maybe this should replace the keyCode > 31 condition.
    {
      var modifiers = [];

      if (event.shiftKey)
        keyChar = keyChar.toUpperCase();
      if (event.metaKey)
        modifiers.push("m");
      if (event.ctrlKey)
        modifiers.push("c");
      if (event.altKey)
        modifiers.push("a");

      for (var i in modifiers)
        keyChar = modifiers[i] + "-" + keyChar;

      if (modifiers.length > 0)
        keyChar = "<" + keyChar + ">";
    }
  }

  if (insertMode && isEscape(event))
  {
    // Note that we can't programmatically blur out of Flash embeds from Javascript.
    if (!isEmbed(event.srcElement)) {
      // Remove focus so the user can't just get himself back into insert mode by typing in the same input box.
      if (isEditable(event.srcElement)) { event.srcElement.blur(); }
      exitInsertMode();
    }
  }
  else if (findMode)
  {
    if (isEscape(event))
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
  else if (isShowingHelpDialog && isEscape(event))
  {
    hideHelpDialog();
  }
  else if (!insertMode && !findMode) {
    if (keyChar) {
      if (currentCompletionKeys.indexOf(keyChar) != -1) {
        event.preventDefault();
        event.stopPropagation();
      }

      keyPort.postMessage(keyChar);
    }
    else if (isEscape(event)) {
      keyPort.postMessage("<ESC>");
    }
  }
}

function refreshCompletionKeys(completionKeys) {
  if (completionKeys)
    currentCompletionKeys = completionKeys;
  else
    chrome.extension.sendRequest({handler: "getCompletionKeys"}, function (response) {
      currentCompletionKeys = response.completionKeys;
    });
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
function isFocusable(element) { return isEditable(element) || isEmbed(element); }

/*
 * Embedded elements like Flash and quicktime players can obtain focus but cannot be programmatically
 * unfocused.
 */
function isEmbed(element) { return ["EMBED", "OBJECT"].indexOf(element.tagName) > 0; }

/*
 * Input or text elements are considered focusable and able to receieve their own keyboard events,
 * and will enter enter mode if focused. Also note that the "contentEditable" attribute can be set on
 * any element which makes it a rich text editor, like the notes on jjot.com.
 * Note: we used to discriminate for text-only inputs, but this is not accurate since all input fields
 * can be controlled via the keyboard, particuarlly SELECT combo boxes.
 */
function isEditable(target) {
  if (target.getAttribute("contentEditable") == "true")
    return true;
  var focusableInputs = ["input", "textarea", "select", "button"];
  return focusableInputs.indexOf(target.tagName.toLowerCase()) >= 0;
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
  performFindInPlace();
  showFindModeHUDForQuery();
}

function handleDeleteForFindMode() {
  if (findModeQuery.length == 0)
  {
    exitFindMode();
    performFindInPlace();
  }
  else
  {
    findModeQuery = findModeQuery.substring(0, findModeQuery.length - 1);
    performFindInPlace();
    showFindModeHUDForQuery();
  }
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
  findModeQueryHasResults = window.find(findModeQuery, false, false, true, false, true, false);
}

function performBackwardsFind() {
  findModeQueryHasResults = window.find(findModeQuery, false, true, true, false, true, false);
}

function showFindModeHUDForQuery() {
  if (findModeQueryHasResults || findModeQuery.length == 0)
    HUD.show("/" + insertSpaces(findModeQuery));
  else
    HUD.show("/" + insertSpaces(findModeQuery + " (No Matches)"));
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

function showHelpDialog(html) {
  if (isShowingHelpDialog || !document.body)
    return;
  isShowingHelpDialog = true;
  var container = document.createElement("div");
  container.id = "vimiumHelpDialogContainer";
  container.innerHTML = html;
  container.getElementsByClassName("closeButton")[0].addEventListener("click", hideHelpDialog, false);
  document.body.appendChild(container);
  var dialog = document.getElementById("vimiumHelpDialog");
  dialog.style.zIndex = "99999998";
  var zoomFactor = currentZoomLevel / 100.0;
  dialog.style.top =
      Math.max((window.innerHeight - dialog.clientHeight * zoomFactor) / 2.0, 20) / zoomFactor + "px";
}

function hideHelpDialog(clickEvent) {
  isShowingHelpDialog = false;
  var helpDialog = document.getElementById("vimiumHelpDialogContainer");
  if (helpDialog)
    helpDialog.parentNode.removeChild(helpDialog);
  clickEvent.preventDefault();
}

/*
 * A heads-up-display (HUD) for showing Vimium page operations.
 * Note: you cannot interact with the HUD until document.body is available.
 */
HUD = {
  _tweenId: -1,
  _displayElement: null,
  _upgradeNotificationElement: null,

  // This HUD is styled to precisely mimick the chrome HUD on Mac. Use the "has_popup_and_link_hud.html"
  // test harness to tweak these styles to match Chrome's. One limitation of our HUD display is that
  // it doesn't sit on top of horizontal scrollbars like Chrome's HUD does.
  _hudCss:
    ".vimiumHUD, .vimiumHUD * {" +
      "line-height: 100%;" +
      "font-size: 11px;" +
      "font-weight: normal;" +
    "}" +
    ".vimiumHUD {" +
      "position: fixed;" +
      "bottom: 0px;" +
      "color: black;" +
      "height: 13px;" +
      "max-width: 400px;" +
      "min-width: 150px;" +
      "text-align: left;" +
      "background-color: #ebebeb;" +
      "padding: 3px 3px 2px 3px;" +
      "border: 1px solid #b3b3b3;" +
      "border-radius: 4px 4px 0 0;" +
      "font-family: Lucida Grande, Arial, Sans;" +
      // One less than vimium's hint markers, so link hints can be shown e.g. for the panel's close button.
      "z-index: 99999998;" +
      "text-shadow: 0px 1px 2px #FFF;" +
      "line-height: 1.0;" +
      "opacity: 0;" +
    "}" +
    ".vimiumHUD a, .vimiumHUD a:hover {" +
      "background: transparent;" +
      "color: blue;" +
      "text-decoration: underline;" +
    "}" +
    ".vimiumHUD a.close-button {" +
      "float:right;" +
      "font-family:courier new;" +
      "font-weight:bold;" +
      "color:#9C9A9A;" +
      "text-decoration:none;" +
      "padding-left:10px;" +
      "margin-top:-1px;" +
      "font-size:14px;" +
    "}" +
    ".vimiumHUD a.close-button:hover {" +
      "color:#333333;" +
      "cursor:default;" +
      "-webkit-user-select:none;" +
    "}",

  _cssHasBeenAdded: false,

  showForDuration: function(text, duration) {
    HUD.show(text);
    HUD._showForDurationTimerId = setTimeout(function() { HUD.hide(); }, duration);
  },

  show: function(text) {
    clearTimeout(HUD._showForDurationTimerId);
    HUD.displayElement().innerHTML = text;
    clearInterval(HUD._tweenId);
    HUD._tweenId = Tween.fade(HUD.displayElement(), 1.0, 150);
    HUD.displayElement().style.display = "";
  },

  showUpgradeNotification: function(version) {
    HUD.upgradeNotificationElement().innerHTML = "Vimium has been updated to " +
      "<a href='https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb'>" +
      version + "</a>.<a class='close-button' href='#'>x</a>";
    var links = HUD.upgradeNotificationElement().getElementsByTagName("a");
    links[0].addEventListener("click", HUD.onUpdateLinkClicked, false);
    links[1].addEventListener("click", function(event) {
      event.preventDefault();
      HUD.onUpdateLinkClicked();
    });
    Tween.fade(HUD.upgradeNotificationElement(), 1.0, 150);
  },

  onUpdateLinkClicked: function(event) {
    HUD.hideUpgradeNotification();
    chrome.extension.sendRequest({ handler: "upgradeNotificationClosed" });
  },

  hideUpgradeNotification: function(clickEvent) {
    Tween.fade(HUD.upgradeNotificationElement(), 0, 150,
      function() { HUD.upgradeNotificationElement().style.display = "none"; });
  },

  updatePageZoomLevel: function(pageZoomLevel) {
    // Since the chrome HUD does not scale with the page's zoom level, neither will this HUD.
    var inverseZoomLevel = (100.0 / pageZoomLevel) * 100;
    if (HUD._displayElement)
      HUD.displayElement().style.zoom = inverseZoomLevel + "%";
    if (HUD._upgradeNotificationElement)
      HUD.upgradeNotificationElement().style.zoom = inverseZoomLevel + "%";
  },

  /*
   * Retrieves the HUD HTML element.
   */
  displayElement: function() {
    if (!HUD._displayElement) {
      HUD._displayElement = HUD.createHudElement();
      // Keep this far enough to the right so that it doesn't collide with the "popups blocked" chrome HUD.
      HUD._displayElement.style.right = "150px";
      HUD.updatePageZoomLevel(currentZoomLevel);
    }
    return HUD._displayElement;
  },

  upgradeNotificationElement: function() {
    if (!HUD._upgradeNotificationElement) {
      HUD._upgradeNotificationElement = HUD.createHudElement();
      // Position this just to the left of our normal HUD.
      HUD._upgradeNotificationElement.style.right = "315px";
      HUD.updatePageZoomLevel(currentZoomLevel);
    }
    return HUD._upgradeNotificationElement;
  },

  createHudElement: function() {
    if (!HUD._cssHasBeenAdded) {
      addCssToPage(HUD._hudCss);
      HUD._cssHasBeenAdded = true;
    }
    var element = document.createElement("div");
    element.className = "vimiumHUD";
    document.body.appendChild(element);
    return element;
  },

  hide: function() {
    clearInterval(HUD._tweenId);
    HUD._tweenId = Tween.fade(HUD.displayElement(), 0, 150,
      function() { HUD.displayElement().style.display = "none"; });
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

/*
 * Adds the given CSS to the page.
 */
function addCssToPage(css) {
  var head = document.getElementsByTagName("head")[0];
  if (!head) {
    console.log("Warning: unable to add CSS to the page.");
    return;
  }
  var style = document.createElement("style");
  style.type = "text/css";
  style.appendChild(document.createTextNode(css));
  head.appendChild(style);
}

// Prevent our content script from being run on iframes -- only allow it to run on the top level DOM "window".
// TODO(philc): We don't want to process multiple keyhandlers etc. when embedded on a page containing IFrames.
// This should be revisited, because sometimes we *do* want to listen inside of the currently focused iframe.
var isIframe = (window.self != window.parent);
if (!isIframe) {
  initializePreDomReady();
  window.addEventListener("DOMContentLoaded", initializeOnDomReady);
}

window.onbeforeunload = function() {
  chrome.extension.sendRequest({ handler: 'updateScrollPosition', scrollX: window.scrollX, scrollY: window.scrollY });
}
