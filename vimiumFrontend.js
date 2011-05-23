/*
 * This content script takes input from its webpage and executes commands locally on behalf of the background
 * page. It must be run prior to domReady so that we perform some operations very early, like setting
 * the page's zoom level. We tell the background page that we're in domReady and ready to accept normal
 * commands by connectiong to a port named "domReady".
 */

var getCurrentUrlHandlers = []; // function(url)

var insertModeLock = null;
var findMode = false;
var findModeQuery = "";
var findModeQueryHasResults = false;
var isShowingHelpDialog = false;
var handlerStack = [];
var keyPort;
var settingPort;
var saveZoomLevelPort;
// Users can disable Vimium on URL patterns via the settings page.
var isEnabledForUrl = true;
// The user's operating system.
var currentCompletionKeys;
var validFirstKeys;
var linkHintCss;

// TODO(philc): This should be pulled from the extension's storage when the page loads.
var currentZoomLevel = 100;

// The types in <input type="..."> that we consider for focusInput command. Right now this is recalculated in
// each content script. Alternatively we could calculate it once in the background page and use a request to
// fetch it each time.
//
// Should we include the HTML5 date pickers here?
var textInputTypes = ["text", "search", "email", "url", "number"];
// The corresponding XPath for such elements.
var textInputXPath = '//input[' +
                     textInputTypes.map(function (type) { return '@type="' + type + '"'; }).join(" or ") +
                     ' or not(@type)]';

var settings = {
  values: {},
  loadedValues: 0,
  valuesToLoad: ["scrollStepSize", "linkHintCharacters", "filterLinkHints"],

  get: function (key) { return this.values[key]; },

  load: function() {
    for (var i in this.valuesToLoad) { this.sendMessage(this.valuesToLoad[i]); }
  },

  sendMessage: function (key) {
    if (!settingPort)
      settingPort = chrome.extension.connect({ name: "getSetting" });
    settingPort.postMessage({ key: key });
  },

  receiveMessage: function (args) {
    // not using 'this' due to issues with binding on callback
    settings.values[args.key] = args.value;
    if (++settings.loadedValues == settings.valuesToLoad.length)
      settings.initializeOnReady();
  },

  initializeOnReady: function () {
    linkHints.init();
  }
};

/*
 * Give this frame a unique id.
 */
frameId = Math.floor(Math.random()*999999999)

var hasModifiersRegex = /^<([amc]-)+.>/;
var googleRegex = /:\/\/[^/]*google[^/]+/;

/*
 * Complete initialization work that sould be done prior to DOMReady, like setting the page's zoom level.
 */
function initializePreDomReady() {
  settings.load();

  checkIfEnabledForUrl();

  var getZoomLevelPort = chrome.extension.connect({ name: "getZoomLevel" });
  if (window.self == window.parent)
    getZoomLevelPort.postMessage({ domain: window.location.host });

  chrome.extension.sendRequest({handler: "getLinkHintCss"}, function (response) {
    linkHintCss = response.linkHintCss;
  });

  refreshCompletionKeys();

  // Send the key to the key handler in the background page.
  keyPort = chrome.extension.connect({ name: "keyDown" });

  chrome.extension.onRequest.addListener(function(request, sender, sendResponse) {
    if (request.name == "hideUpgradeNotification") {
      HUD.hideUpgradeNotification();
    } else if (request.name == "showUpgradeNotification" && isEnabledForUrl) {
      HUD.showUpgradeNotification(request.version);
    } else if (request.name == "showHelpDialog") {
      if (isShowingHelpDialog)
        hideHelpDialog();
      else
        showHelpDialog(request.dialogHtml, request.frameId);
    } else if (request.name == "focusFrame") {
      if (frameId == request.frameId)
        focusThisFrame(request.highlight);
    } else if (request.name == "refreshCompletionKeys") {
      refreshCompletionKeys(request);
    }
    sendResponse({}); // Free up the resources used by this open connection.
  });

  chrome.extension.onConnect.addListener(function(port, name) {
    if (port.name == "executePageCommand") {
      port.onMessage.addListener(function(args) {
        if (frameId == args.frameId) {
          if (args.passCountToFunction) {
            utils.invokeCommandString(args.command, [args.count]);
          } else {
            for (var i = 0; i < args.count; i++) { utils.invokeCommandString(args.command); }
          }
        }

        refreshCompletionKeys(args);
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
    } else if (port.name == "returnSetting") {
      port.onMessage.addListener(settings.receiveMessage);
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
  document.addEventListener("keypress", onKeypress, true);
  document.addEventListener("keyup", onKeyup, true);
  document.addEventListener("focus", onFocusCapturePhase, true);
  document.addEventListener("blur", onBlurCapturePhase, true);
  enterInsertModeIfElementIsFocused();
}


/*
 * The backend needs to know which frame has focus.
 */
window.addEventListener("focus", function(e) {
  chrome.extension.sendRequest({ handler: "frameFocused", frameId: frameId });
});

/*
 * Called from the backend in order to change frame focus.
 */
function focusThisFrame(shouldHighlight) {
  window.focus();
  if (document.body && shouldHighlight) {
    var borderWas = document.body.style.border;
    document.body.style.border = '5px solid yellow';
    setTimeout(function(){document.body.style.border = borderWas}, 200);
  }
}

/*
 * Initialization tasks that must wait for the document to be ready.
 */
function initializeOnDomReady() {
  registerFrameIfSizeAvailable(window.top == window.self);

  if (isEnabledForUrl)
    enterInsertModeIfElementIsFocused();

  // Tell the background page we're in the dom ready state.
  chrome.extension.connect({ name: "domReady" });
};

// This is a little hacky but sometimes the size wasn't available on domReady?
function registerFrameIfSizeAvailable (is_top) {
  if (innerWidth != undefined && innerWidth != 0 && innerHeight != undefined && innerHeight != 0)
    chrome.extension.sendRequest({ handler: "registerFrame", frameId: frameId,
        area: innerWidth * innerHeight, is_top: is_top, total: frames.length + 1 });
  else
    setTimeout(function () { registerFrameIfSizeAvailable(is_top); }, 100);
}

/*
 * Checks the currently focused element of the document and will enter insert mode if that element is focusable.
 */
function enterInsertModeIfElementIsFocused() {
  // Enter insert mode automatically if there's already a text box focused.
  if (document.activeElement && isEditable(document.activeElement))
    enterInsertMode(document.activeElement);
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
  currentZoomLevel += 20;
  setAndSaveZoom();
}

function zoomOut() {
  currentZoomLevel -= 20;
  setAndSaveZoom();
}

function zoomReset() {
  currentZoomLevel = 100;
  setAndSaveZoom();
}

function setAndSaveZoom() {
  setPageZoomLevel(currentZoomLevel, true);
  saveZoomLevel(window.location.host, currentZoomLevel);
}

function scrollToBottom() { window.scrollTo(window.pageXOffset, document.body.scrollHeight); }
function scrollToTop() { window.scrollTo(window.pageXOffset, 0); }
function scrollToLeft() { window.scrollTo(0, window.pageYOffset); }
function scrollToRight() { window.scrollTo(document.body.scrollWidth, window.pageYOffset); }
function scrollUp() { window.scrollBy(0, -1 * settings.get("scrollStepSize")); }
function scrollDown() { window.scrollBy(0, settings.get("scrollStepSize")); }
function scrollPageUp() { window.scrollBy(0, -1 * window.innerHeight / 2); }
function scrollPageDown() { window.scrollBy(0, window.innerHeight / 2); }
function scrollFullPageUp() { window.scrollBy(0, -window.innerHeight); }
function scrollFullPageDown() { window.scrollBy(0, window.innerHeight); }
function scrollLeft() { window.scrollBy(-1 * settings.get("scrollStepSize"), 0); }
function scrollRight() { window.scrollBy(settings.get("scrollStepSize"), 0); }

function focusInput(count) {
  var results = document.evaluate(textInputXPath,
                                  document.documentElement, null,
                                  XPathResult.ORDERED_NODE_ITERATOR_TYPE, null);

  var lastInputBox;
  var i = 0;

  while (i < count) {
    i += 1;

    var currentInputBox = results.iterateNext();
    if (!currentInputBox) { break; }

    lastInputBox = currentInputBox;
  }

  if (lastInputBox) { lastInputBox.focus(); }
}

function reload() { window.location.reload(); }
function goBack() { history.back(); }
function goForward() { history.forward(); }

function goUp(count) {
  var url = window.location.href;
  if (url[url.length-1] == '/')
    url = url.substring(0, url.length - 1);

  var urlsplit = url.split('/');
  // make sure we haven't hit the base domain yet
  if (urlsplit.length > 3) {
    urlsplit = urlsplit.slice(0, Math.max(3, urlsplit.length - count));
    window.location.href = urlsplit.join('/');
  }
}

function toggleViewSource() {
  getCurrentUrlHandlers.push(toggleViewSourceCallback);

  var getCurrentUrlPort = chrome.extension.connect({ name: "getCurrentTabUrl" });
  getCurrentUrlPort.postMessage({});
}

function copyCurrentUrl() {
  // TODO(ilya): When the following bug is fixed, revisit this approach of sending back to the background page
  // to copy.
  // http://code.google.com/p/chromium/issues/detail?id=55188
  //getCurrentUrlHandlers.push(function (url) { Clipboard.copy(url); });
  getCurrentUrlHandlers.push(function (url) { chrome.extension.sendRequest({ handler: "copyToClipboard", data: url }); });

  // TODO(ilya): Convert to sendRequest.
  var getCurrentUrlPort = chrome.extension.connect({ name: "getCurrentTabUrl" });
  getCurrentUrlPort.postMessage({});

	HUD.showForDuration("Yanked URL", 1000);
}

function toggleViewSourceCallback(url) {
  if (url.substr(0, 12) == "view-source:")
  {
    url = url.substr(12, url.length - 12);
  }
  else { url = "view-source:" + url; }
  chrome.extension.sendRequest({handler: "openUrlInNewTab", url: url, selected: true});
}

/**
 * Sends everything except i & ESC to the handler in background_page. i & ESC are special because they control
 * insert mode which is local state to the page. The key will be are either a single ascii letter or a
 * key-modifier pair, e.g. <c-a> for control a.
 *
 * Note that some keys will only register keydown events and not keystroke events, e.g. ESC.
 */
function onKeypress(event) {
  if (!bubbleEvent('keypress', event))
    return;

  var keyChar = "";

  // Ignore modifier keys by themselves.
  if (event.keyCode > 31) {
    keyChar = String.fromCharCode(event.charCode);

    // Enter insert mode when the user enables the native find interface.
    if (keyChar == "f" && isPrimaryModifierKey(event)) {
      enterInsertMode();
      return;
    }

    if (keyChar) {
      if (findMode) {
        handleKeyCharForFindMode(keyChar);

        // Don't let the space scroll us if we're searching.
        if (event.keyCode == keyCodes.space)
          event.preventDefault();
      } else if (!isInsertMode() && !findMode) {
        if (currentCompletionKeys.indexOf(keyChar) != -1) {
          event.preventDefault();
          event.stopPropagation();
        }

        keyPort.postMessage({keyChar:keyChar, frameId:frameId});
      }
    }
  }
}

function bubbleEvent(type, event) {
  for (var i = handlerStack.length-1; i >= 0; i--) {
    // We need to check for existence of handler because the last function call may have caused the release of
    // more than one handler.
    if (handlerStack[i] && handlerStack[i][type] && !handlerStack[i][type](event))
      return false;
  }
  return true;
}

function onKeydown(event) {
  if (!bubbleEvent('keydown', event))
    return;

  var keyChar = "";

  // handle modifiers being pressed.don't handle shiftKey alone (to avoid / being interpreted as ?
  if (event.metaKey && event.keyCode > 31 || event.ctrlKey && event.keyCode > 31 || event.altKey && event.keyCode > 31) {
    keyChar = getKeyChar(event);

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

      if (modifiers.length > 0 || keyChar.length > 1)
          keyChar = "<" + keyChar + ">";
    }
  }

  if (isInsertMode() && isEscape(event))
  {
    // Note that we can't programmatically blur out of Flash embeds from Javascript.
    if (!isEmbed(event.srcElement)) {
      // Remove focus so the user can't just get himself back into insert mode by typing in the same input box.
      if (isEditable(event.srcElement)) { event.srcElement.blur(); }
      exitInsertMode();

      // Added to prevent Google Instant from reclaiming the keystroke and putting us back into the search box.
      if (isGoogleSearch())
        event.stopPropagation();
    }
  }
  else if (findMode)
  {
    if (isEscape(event))
      exitFindMode();
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
  else if (!isInsertMode() && !findMode) {
    if (keyChar) {
        if (currentCompletionKeys.indexOf(keyChar) != -1) {
            event.preventDefault();
            event.stopPropagation();
        }

        keyPort.postMessage({keyChar:keyChar, frameId:frameId});
    }
    else if (isEscape(event)) {
      keyPort.postMessage({keyChar:"<ESC>", frameId:frameId});
    }
  }

  // Added to prevent propagating this event to other listeners if it's one that'll trigger a Vimium command.
  // The goal is to avoid the scenario where Google Instant Search uses every keydown event to dump us
  // back into the search box. As a side effect, this should also prevent overriding by other sites.
  //
  // Subject to internationalization issues since we're using keyIdentifier instead of charCode (in keypress).
  //
  // TOOD(ilya): Revisit this. Not sure it's the absolute best approach.
  if (keyChar == "" && !isInsertMode()
                    && (currentCompletionKeys.indexOf(getKeyChar(event)) != -1 || validFirstKeys[getKeyChar(event)]))
    event.stopPropagation();
}

function onKeyup() {
  if (!bubbleEvent('keyup', event))
    return;
}

function checkIfEnabledForUrl() {
    var url = window.location.toString();

    chrome.extension.sendRequest({ handler: "isEnabledForUrl", url: url }, function (response) {
      isEnabledForUrl = response.isEnabledForUrl;
      if (isEnabledForUrl)
        initializeWhenEnabled();
      else if (HUD.isReady())
        // Quickly hide any HUD we might already be showing, e.g. if we entered insert mode on page load.
        HUD.hide();
    });
}

// TODO(ilya): This just checks if "google" is in the domain name. Probably should be more targeted.
function isGoogleSearch() {
  var url = window.location.toString();
  return !!url.match(googleRegex);
}

function refreshCompletionKeys(response) {
  if (response) {
    currentCompletionKeys = response.completionKeys;

    if (response.validFirstKeys)
      validFirstKeys = response.validFirstKeys;
  } else {
    chrome.extension.sendRequest({ handler: "getCompletionKeys" }, refreshCompletionKeys);
  }
}

function onFocusCapturePhase(event) {
  if (isFocusable(event.target))
    enterInsertMode(event.target);
}

function onBlurCapturePhase(event) {
  if (isFocusable(event.target))
    exitInsertMode(event.target);
}

/*
 * Returns true if the element is focusable. This includes embeds like Flash, which steal the keybaord focus.
 */
function isFocusable(element) { return isEditable(element) || isEmbed(element); }

/*
 * Embedded elements like Flash and quicktime players can obtain focus but cannot be programmatically
 * unfocused.
 */
function isEmbed(element) { return ["embed", "object"].indexOf(element.nodeName.toLowerCase()) > 0; }

/*
 * Input or text elements are considered focusable and able to receieve their own keyboard events,
 * and will enter enter mode if focused. Also note that the "contentEditable" attribute can be set on
 * any element which makes it a rich text editor, like the notes on jjot.com.
 */
function isEditable(target) {
  if (target.isContentEditable)
    return true;
  var nodeName = target.nodeName.toLowerCase();
  // use a blacklist instead of a whitelist because new form controls are still being implemented for html5
  var noFocus = ["radio", "checkbox"];
  if (nodeName == "input" && noFocus.indexOf(target.type) == -1)
    return true;
  var focusableElements = ["textarea", "select"];
  return focusableElements.indexOf(nodeName) >= 0;
}

// We cannot count on 'focus' and 'blur' events to happen sequentially. For example, if blurring element A
// causes element B to come into focus, we may get 'B focus' before 'A blur'. Thus we only leave insert mode
// when the last editable element that came into focus -- which insertModeLock points to -- has been blurred.
// If insert mode is entered manually (via pressing 'i'), then we set insertModeLock to 'undefined', and only
// leave insert mode when the user presses <ESC>.
function enterInsertMode(target) {
  insertModeLock = target;
  HUD.show("Insert mode");
}

function exitInsertMode(target) {
  if (target === undefined || insertModeLock === target) {
    insertModeLock = null;
    HUD.hide();
  }
}

function isInsertMode() {
  return insertModeLock !== null;
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

  executeFind();
}

function executeFind(backwards) {
  findModeQueryHasResults = window.find(findModeQuery, false, backwards, true, false, true, false);
}

function focusFoundLink() {
  if (findModeQueryHasResults) {
    var link = getLinkFromSelection();
    if (link) link.focus();
  }
}

function findAndFocus(backwards) {
  executeFind(backwards);
  focusFoundLink();
}

function performFind() {
  findAndFocus();
}

function performBackwardsFind() {
  findAndFocus(true);
}

function getLinkFromSelection() {
  var node = window.getSelection().anchorNode;
  while (node.nodeName.toLowerCase() !== 'body') {
    if (node.nodeName.toLowerCase() === 'a') return node;
    node = node.parentNode;
  }
  return null;
}

function findAndFollowLink(linkStrings) {
  for (i = 0; i < linkStrings.length; i++) {
    var hasResults = window.find(linkStrings[i], false, true, true, false, true, false);
    if (hasResults) {
      var link = getLinkFromSelection();
      if (link) {
        window.location = link.href;
        return true;
      }
    }
  }
  return false;
}

function findAndFollowRel(value) {
  var relTags = ['link', 'a', 'area'];
  for (i = 0; i < relTags.length; i++) {
    var elements = document.getElementsByTagName(relTags[i]);
    for (j = 0; j < elements.length; j++) {
      if (elements[j].hasAttribute('rel') && elements[j].rel == value) {
        window.location = elements[j].href;
        return true;
      }
    }
  }
}

function goPrevious() {
  // NOTE : If a page contains both a single angle-bracket link and a double angle-bracket link, then in most
  // cases the single bracket link will be "prev/next page" and the double bracket link will be "first/last
  // page", so check for single bracket first.
  var previousStrings = ["\bprev\b", "\bprevious\b", "\bback\b", "<", "←", "«", "≪", "<<"];
  findAndFollowRel('prev') || findAndFollowLink(previousStrings);
}

function goNext() {
  var nextStrings = ["\bnext\b", "\bmore\b", ">", "→", "»", "≫", ">>"];
  findAndFollowRel('next') || findAndFollowLink(nextStrings);
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
    else //  &#8203; is a zero-width space
      newQuery = newQuery + query[i] + "<span>&#8203;</span>";
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
  focusFoundLink();
  HUD.hide();
}

function showHelpDialog(html, fid) {
  if (isShowingHelpDialog || !document.body || fid != frameId)
    return;
  isShowingHelpDialog = true;
  var container = document.createElement("div");
  container.id = "vimiumHelpDialogContainer";

  document.body.appendChild(container);

  container.innerHTML = html;
  // This is necessary because innerHTML does not evaluate javascript embedded in <script> tags.
  var scripts = Array.prototype.slice.call(container.getElementsByTagName("script"));
  scripts.forEach(function(script) { eval(script.text); });

  container.getElementsByClassName("closeButton")[0].addEventListener("click", hideHelpDialog, false);
  container.getElementsByClassName("optionsPage")[0].addEventListener("click",
      function() { chrome.extension.sendRequest({ handler: "openOptionsPageInNewTab" }); }, false);
}

function hideHelpDialog(clickEvent) {
  isShowingHelpDialog = false;
  var helpDialog = document.getElementById("vimiumHelpDialogContainer");
  if (helpDialog)
    helpDialog.parentNode.removeChild(helpDialog);
  if (clickEvent)
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
      "width: auto;" +
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
    head = document.createElement("head");
    document.documentElement.appendChild(head);
  }
  var style = document.createElement("style");
  style.type = "text/css";
  style.appendChild(document.createTextNode(css));
  head.appendChild(style);
}

initializePreDomReady();
window.addEventListener("DOMContentLoaded", initializeOnDomReady);

window.onbeforeunload = function() {
  chrome.extension.sendRequest({ handler: "updateScrollPosition",
      scrollX: window.scrollX, scrollY: window.scrollY });
}
