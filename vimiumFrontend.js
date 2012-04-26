/*
 * This content script takes input from its webpage and executes commands locally on behalf of the background
 * page. It must be run prior to domReady so that we perform some operations very early. We tell the
 * background page that we're in domReady and ready to accept normal commands by connectiong to a port named
 * "domReady".
 */
var getCurrentUrlHandlers = []; // function(url)

var insertModeLock = null;
var findMode = false;
var findModeQuery = { rawQuery: "" };
var findModeQueryHasResults = false;
var findModeAnchorNode = null;
var isShowingHelpDialog = false;
var handlerStack = [];
var keyPort;
// Users can disable Vimium on URL patterns via the settings page.
var isEnabledForUrl = true;
// The user's operating system.
var currentCompletionKeys;
var validFirstKeys;
var linkHintCss;
var activatedElement;

// The types in <input type="..."> that we consider for focusInput command. Right now this is recalculated in
// each content script. Alternatively we could calculate it once in the background page and use a request to
// fetch it each time.
//
// Should we include the HTML5 date pickers here?

// The corresponding XPath for such elements.
var textInputXPath = (function() {
  var textInputTypes = ["text", "search", "email", "url", "number", "password"];
  var inputElements = ["input[" +
    "(" + textInputTypes.map(function(type) {return '@type="' + type + '"'}).join(" or ") + "or not(@type))" +
    " and not(@disabled or @readonly)]",
    "textarea", "*[@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"];
  return domUtils.makeXPath(inputElements);
})();

/**
 * settings provides a browser-global localStorage-backed dict. get() and set() are synchronous, but load()
 * must be called beforehand to ensure get() will return up-to-date values.
 */
var settings = {
  port: null,
  values: {},
  loadedValues: 0,
  valuesToLoad: ["scrollStepSize", "linkHintCharacters", "filterLinkHints", "hideHud", "previousPatterns",
      "nextPatterns", "findModeRawQuery"],
  isLoaded: false,
  eventListeners: {},

  init: function () {
    this.port = chrome.extension.connect({ name: "settings" });
    this.port.onMessage.addListener(this.receiveMessage);
  },

  get: function (key) { return this.values[key]; },

  set: function (key, value) {
    if (!this.port)
      this.init();

    this.values[key] = value;
    this.port.postMessage({ operation: "set", key: key, value: value });
  },

  load: function() {
    if (!this.port)
      this.init();

    for (var i in this.valuesToLoad) {
      this.port.postMessage({ operation: "get", key: this.valuesToLoad[i] });
    }
  },

  receiveMessage: function (args) {
    // not using 'this' due to issues with binding on callback
    settings.values[args.key] = args.value;
    // since load() can be called more than once, loadedValues can be greater than valuesToLoad, but we test
    // for equality so initializeOnReady only runs once
    if (++settings.loadedValues == settings.valuesToLoad.length) {
      settings.isLoaded = true;
      var listener;
      while (listener = settings.eventListeners["load"].pop())
        listener();
    }
  },

  addEventListener: function(eventName, callback) {
    if (!(eventName in this.eventListeners))
      this.eventListeners[eventName] = [];
    this.eventListeners[eventName].push(callback);
  },

};

/*
 * Give this frame a unique id.
 */
frameId = Math.floor(Math.random()*999999999)

var hasModifiersRegex = /^<([amc]-)+.>/;

/*
 * Complete initialization work that sould be done prior to DOMReady.
 */
function initializePreDomReady() {
  settings.addEventListener("load", linkHints.init.bind(linkHints));
  settings.load();

  checkIfEnabledForUrl();

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
        if (args.scrollX > 0 || args.scrollY > 0) {
          domUtils.documentReady(function() { window.scrollBy(args.scrollX, args.scrollY); });
        }
      });
    } else if (port.name == "returnCurrentTabUrl") {
      port.onMessage.addListener(function(args) {
        if (getCurrentUrlHandlers.length > 0) { getCurrentUrlHandlers.pop()(args.url); }
      });
    } else if (port.name == "refreshCompletionKeys") {
      port.onMessage.addListener(function (args) {
        refreshCompletionKeys(args.completionKeys);
      });
    } else if (port.name == "getActiveState") {
      port.onMessage.addListener(function(args) {
        port.postMessage({ enabled: isEnabledForUrl });
      });
    } else if (port.name == "disableVimium") {
      port.onMessage.addListener(function(args) { disableVimium(); });
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
  document.addEventListener("DOMActivate", onDOMActivate, true);
  enterInsertModeIfElementIsFocused();
}

/*
 * Used to disable Vimium without needing to reload the page.
 * This is called if the current page's url is blacklisted using the popup UI.
 */
function disableVimium() {
  document.removeEventListener("keydown", onKeydown, true);
  document.removeEventListener("keypress", onKeypress, true);
  document.removeEventListener("keyup", onKeyup, true);
  document.removeEventListener("focus", onFocusCapturePhase, true);
  document.removeEventListener("blur", onBlurCapturePhase, true);
  document.removeEventListener("DOMActivate", onDOMActivate, true);
  isEnabledForUrl = false;
}

/*
 * The backend needs to know which frame has focus.
 */
window.addEventListener("focus", function(e) {
  // settings may have changed since the frame last had focus
  settings.load();
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
 * Enters insert mode if the currently focused element in the DOM is focusable.
 */
function enterInsertModeIfElementIsFocused() {
  if (document.activeElement && isEditable(document.activeElement) && !findMode)
    enterInsertModeWithoutShowingIndicator(document.activeElement);
}

function onDOMActivate(event) {
  activatedElement = event.target;
}

/**
 * activatedElement is different from document.activeElement -- the latter seems to be reserved mostly for
 * input elements. This mechanism allows us to decide whether to scroll a div or to scroll the whole document.
 */
function scrollActivatedElementBy(direction, amount) {
  // if this is called before domReady, just use the window scroll function
  if (!document.body) {
    if (direction === "x")
      window.scrollBy(amount, 0);
    else // "y"
      window.scrollBy(0, amount);
    return;
  }

  // TODO refactor and put this together with the code in getVisibleClientRect
  function isRendered(element) {
    var computedStyle = window.getComputedStyle(element, null);
    return !(computedStyle.getPropertyValue('visibility') != 'visible' ||
        computedStyle.getPropertyValue('display') == 'none');
  }

  if (!activatedElement || !isRendered(activatedElement))
    activatedElement = document.body;

  scrollName = direction === "x" ? "scrollLeft" : "scrollTop";

  // Chrome does not report scrollHeight accurately for nodes with pseudo-elements of height 0 (bug 110149).
  // Therefore we just try to increase scrollTop blindly -- if it fails we know we have reached the end of the
  // content.
  if (amount !== 0) {
    var element = activatedElement;
    do {
      var oldScrollValue = element[scrollName];
      element[scrollName] += amount;
      var lastElement = element;
      // we may have an orphaned element. if so, just scroll the body element.
      element = element.parentElement || document.body;
    } while(lastElement[scrollName] == oldScrollValue && lastElement != document.body);
  }

  // if the activated element has been scrolled completely offscreen, subsequent changes in its scroll
  // position will not provide any more visual feedback to the user. therefore we deactivate it so that
  // subsequent scrolls only move the parent element.
  var rect = activatedElement.getBoundingClientRect();
  if (rect.bottom < 0 || rect.top > window.innerHeight ||
      rect.right < 0 || rect.left > window.innerWidth)
    activatedElement = lastElement;
}

function scrollToBottom() { window.scrollTo(window.pageXOffset, document.body.scrollHeight); }
function scrollToTop() { window.scrollTo(window.pageXOffset, 0); }
function scrollToLeft() { window.scrollTo(0, window.pageYOffset); }
function scrollToRight() { window.scrollTo(document.body.scrollWidth, window.pageYOffset); }
function scrollUp() { scrollActivatedElementBy("y", -1 * settings.get("scrollStepSize")); }
function scrollDown() { scrollActivatedElementBy("y", parseFloat(settings.get("scrollStepSize"))); }
function scrollPageUp() { scrollActivatedElementBy("y", -1 * window.innerHeight / 2); }
function scrollPageDown() { scrollActivatedElementBy("y", window.innerHeight / 2); }
function scrollFullPageUp() { scrollActivatedElementBy("y", -window.innerHeight); }
function scrollFullPageDown() { scrollActivatedElementBy("y", window.innerHeight); }
function scrollLeft() { scrollActivatedElementBy("x", -1 * settings.get("scrollStepSize")); }
function scrollRight() { scrollActivatedElementBy("x", parseFloat(settings.get("scrollStepSize"))); }

function focusInput(count) {
  var results = domUtils.evaluateXPath(textInputXPath, XPathResult.ORDERED_NODE_ITERATOR_TYPE);

  var lastInputBox;
  var i = 0;

  while (i < count) {
    var currentInputBox = results.iterateNext();
    if (!currentInputBox) { break; }

    if (domUtils.getVisibleClientRect(currentInputBox) === null)
        continue;

    lastInputBox = currentInputBox;

    i += 1;
  }

  if (lastInputBox) { lastInputBox.focus(); }
}

function reload() { window.location.reload(); }
function goBack(count) { history.go(-count); }
function goForward(count) { history.go(count); }

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
      enterInsertModeWithoutShowingIndicator();
      return;
    }

    if (keyChar) {
      if (findMode) {
        handleKeyCharForFindMode(keyChar);
        suppressEvent(event);
      } else if (!isInsertMode() && !findMode) {
        if (currentCompletionKeys.indexOf(keyChar) != -1)
          suppressEvent(event);

        keyPort.postMessage({keyChar:keyChar, frameId:frameId});
      }
    }
  }
}

/**
 * Called whenever we receive a key event.  Each individual handler has the option to stop the event's
 * propagation by returning a falsy value.
 */
function bubbleEvent(type, event) {
  for (var i = handlerStack.length-1; i >= 0; i--) {
    // We need to check for existence of handler because the last function call may have caused the release of
    // more than one handler.
    if (handlerStack[i] && handlerStack[i][type] && !handlerStack[i][type](event)) {
      suppressEvent(event);
      return false;
    }
  }
  return true;
}

function suppressEvent(event) {
  event.preventDefault();
  event.stopPropagation();
}

function onKeydown(event) {
  if (!bubbleEvent('keydown', event))
    return;

  var keyChar = "";

  // handle special keys, and normal input keys with modifiers being pressed. don't handle shiftKey alone (to
  // avoid / being interpreted as ?
  if (((event.metaKey || event.ctrlKey || event.altKey) && event.keyCode > 31)
      || event.keyIdentifier.slice(0, 2) != "U+") {
    keyChar = getKeyChar(event);

    if (keyChar != "") { // Again, ignore just modifiers. Maybe this should replace the keyCode>31 condition.
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

  if (isInsertMode() && isEscape(event)) {
    // Note that we can't programmatically blur out of Flash embeds from Javascript.
    if (!isEmbed(event.srcElement)) {
      // Remove focus so the user can't just get himself back into insert mode by typing in the same input
      // box.
      if (isEditable(event.srcElement))
        event.srcElement.blur();
      exitInsertMode();
      suppressEvent(event);
    }
  }
  else if (findMode) {
    if (isEscape(event)) {
      handleEscapeForFindMode();
      suppressEvent(event);
    }
    else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
      handleDeleteForFindMode();
      suppressEvent(event);
    }
    else if (event.keyCode == keyCodes.enter) {
      handleEnterForFindMode();
      suppressEvent(event);
    }
    else if (!modifiers) {
      event.stopPropagation();
    }
  }
  else if (isShowingHelpDialog && isEscape(event)) {
    hideHelpDialog();
  }
  else if (!isInsertMode() && !findMode) {
    if (keyChar) {
      if (currentCompletionKeys.indexOf(keyChar) != -1)
        suppressEvent(event);

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
  if (keyChar == "" && !isInsertMode() && (currentCompletionKeys.indexOf(getKeyChar(event)) != -1 ||
      isValidFirstKey(getKeyChar(event))))
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

function refreshCompletionKeys(response) {
  if (response) {
    currentCompletionKeys = response.completionKeys;

    if (response.validFirstKeys)
      validFirstKeys = response.validFirstKeys;
  }
  else {
    chrome.extension.sendRequest({ handler: "getCompletionKeys" }, refreshCompletionKeys);
  }
}

function isValidFirstKey(keyChar) {
  return validFirstKeys[keyChar] || /[1-9]/.test(keyChar);
}

function onFocusCapturePhase(event) {
  if (isFocusable(event.target) && !findMode)
    enterInsertModeWithoutShowingIndicator(event.target);
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

/*
 * Enters insert mode and show an "Insert mode" message. Showing the UI is only useful when entering insert
 * mode manually by pressing "i". In most cases we do not show any UI (enterInsertModeWithoutShowingIndicator)
 */
function enterInsertMode(target) {
  enterInsertModeWithoutShowingIndicator(target);
  HUD.show("Insert mode");
}

/*
 * We cannot count on 'focus' and 'blur' events to happen sequentially. For example, if blurring element A
 * causes element B to come into focus, we may get "B focus" before "A blur". Thus we only leave insert mode
 * when the last editable element that came into focus -- which insertModeLock points to -- has been blurred.
 * If insert mode is entered manually (via pressing 'i'), then we set insertModeLock to 'undefined', and only
 * leave insert mode when the user presses <ESC>.
 */
function enterInsertModeWithoutShowingIndicator(target) { insertModeLock = target; }

function exitInsertMode(target) {
  if (target === undefined || insertModeLock === target) {
    insertModeLock = null;
    HUD.hide();
  }
}

function isInsertMode() { return insertModeLock !== null; }

// should be called whenever rawQuery is modified.
function updateFindModeQuery() {
  // the query can be treated differently (e.g. as a plain string versus regex depending on the presence of
  // escape sequences. '\' is the escape character and needs to be escaped itself to be used as a normal
  // character. here we grep for the relevant escape sequences.
  findModeQuery.isRegex = false;
  var hasNoIgnoreCaseFlag = false;
  findModeQuery.parsedQuery = findModeQuery.rawQuery.replace(/\\./g, function(match) {
    switch (match) {
      case "\\r":
        findModeQuery.isRegex = true;
        return '';
      case "\\I":
        hasNoIgnoreCaseFlag = true;
        return '';
      case "\\\\":
        return "\\";
      default:
        return match;
    }
  });

  // default to 'smartcase' mode, unless noIgnoreCase is explicitly specified
  findModeQuery.ignoreCase = !hasNoIgnoreCaseFlag && !/[A-Z]/.test(findModeQuery.parsedQuery);

  // if we are dealing with a regex, grep for all matches in the text, and then call window.find() on them
  // sequentially so the browser handles the scrolling / text selection.
  if (findModeQuery.isRegex) {
    try {
      var pattern = new RegExp(findModeQuery.parsedQuery, "g" + (findModeQuery.ignoreCase ? "i" : ""));
    }
    catch (e) {
      // if we catch a SyntaxError, assume the user is not done typing yet and return quietly
      return;
    }
    // innerText will not return the text of hidden elements, and strip out tags while preserving newlines
    var text = document.body.innerText;
    findModeQuery.regexMatches = text.match(pattern);
    findModeQuery.activeRegexIndex = 0;
  }
}

function handleKeyCharForFindMode(keyChar) {
  findModeQuery.rawQuery += keyChar;
  updateFindModeQuery();
  performFindInPlace();
  showFindModeHUDForQuery();
}

function handleEscapeForFindMode() {
  exitFindMode();
  document.body.classList.remove("vimiumFindMode");
  // removing the class does not re-color existing selections. we recreate the current selection so it reverts
  // back to the default color.
  var selection = window.getSelection();
  if (!selection.isCollapsed) {
    var range = window.getSelection().getRangeAt(0);
    window.getSelection().removeAllRanges();
    window.getSelection().addRange(range);
  }
  focusFoundLink() || selectFoundInputElement();
}

function handleDeleteForFindMode() {
  if (findModeQuery.rawQuery.length == 0) {
    exitFindMode();
    performFindInPlace();
  }
  else {
    findModeQuery.rawQuery = findModeQuery.rawQuery.substring(0, findModeQuery.rawQuery.length - 1);
    updateFindModeQuery();
    performFindInPlace();
    showFindModeHUDForQuery();
  }
}

// <esc> sends us into insert mode if possible, but <cr> does not.
// <esc> corresponds approximately to 'nevermind, I have found it already' while <cr> means 'I want to save
// this query and do more searches with it'
function handleEnterForFindMode() {
  exitFindMode();
  focusFoundLink();
  document.body.classList.add("vimiumFindMode");
  settings.set("findModeRawQuery", findModeQuery.rawQuery);
}

function performFindInPlace() {
  var cachedScrollX = window.scrollX;
  var cachedScrollY = window.scrollY;

  var query = findModeQuery.isRegex ? getNextQueryFromRegexMatches(0) : findModeQuery.parsedQuery;

  // Search backwards first to "free up" the current word as eligible for the real forward search. This allows
  // us to search in place without jumping around between matches as the query grows.
  executeFind(query, { backwards: true, caseSensitive: !findModeQuery.ignoreCase });

  // We need to restore the scroll position because we might've lost the right position by searching
  // backwards.
  window.scrollTo(cachedScrollX, cachedScrollY);

  findModeQueryHasResults = executeFind(query, { caseSensitive: !findModeQuery.ignoreCase });
}

// :options is an optional dict. valid parameters are 'caseSensitive' and 'backwards'.
function executeFind(query, options) {
  options = options || {};

  // rather hacky, but this is our way of signalling to the insertMode listener not to react to the focus
  // changes that find() induces.
  var oldFindMode = findMode;
  findMode = true;

  document.body.classList.add("vimiumFindMode");

  // prevent find from matching its own search query in the HUD
  HUD.hide(true);
  // ignore the selectionchange event generated by find()
  document.removeEventListener("selectionchange",restoreDefaultSelectionHighlight, true);
  var rv = window.find(query, options.caseSensitive, options.backwards, true, false, true, false);
  setTimeout(function() {
    document.addEventListener("selectionchange", restoreDefaultSelectionHighlight, true);
  }, 0);

  findMode = oldFindMode;
  // we need to save the anchor node here because <esc> seems to nullify it, regardless of whether we do
  // preventDefault()
  findModeAnchorNode = document.getSelection().anchorNode;
  return rv;
}

function restoreDefaultSelectionHighlight() {
  document.body.classList.remove("vimiumFindMode");
}

function focusFoundLink() {
  if (findModeQueryHasResults) {
    var link = getLinkFromSelection();
    if (link)
      link.focus();
  }
}

function isDOMDescendant(parent, child) {
  var node = child;
  while (node !== null) {
    if (node === parent)
      return true;
    node = node.parentNode;
  }
  return false;
}

function selectFoundInputElement() {
  // if the found text is in an input element, getSelection().anchorNode will be null, so we use activeElement
  // instead. however, since the last focused element might not be the one currently pointed to by find (e.g.
  // the current one might be disabled and therefore unable to receive focus), we use the approximate
  // heuristic of checking that the last anchor node is an ancestor of our element.
  if (findModeQueryHasResults && domUtils.isSelectable(document.activeElement) &&
      isDOMDescendant(findModeAnchorNode, document.activeElement)) {
    domUtils.simulateSelect(document.activeElement);
    // the element has already received focus via find(), so invoke insert mode manually
    enterInsertModeWithoutShowingIndicator(document.activeElement);
  }
}

function getNextQueryFromRegexMatches(stepSize) {
  if (!findModeQuery.regexMatches)
    return ""; // find()ing an empty query always returns false

  var totalMatches = findModeQuery.regexMatches.length;
  findModeQuery.activeRegexIndex += stepSize + totalMatches;
  findModeQuery.activeRegexIndex %= totalMatches;

  return findModeQuery.regexMatches[findModeQuery.activeRegexIndex];
}

function findAndFocus(backwards) {
  // check if the query has been changed by a script in another frame
  var mostRecentQuery = settings.get("findModeRawQuery") || "";
  if (mostRecentQuery !== findModeQuery.rawQuery) {
    findModeQuery.rawQuery = mostRecentQuery;
    updateFindModeQuery();
  }

  var query = findModeQuery.isRegex ? getNextQueryFromRegexMatches(backwards ? -1 : 1) :
                                      findModeQuery.parsedQuery;

  findModeQueryHasResults = executeFind(query, { backwards: backwards, caseSensitive: !findModeQuery.ignoreCase });

  if (!findModeQueryHasResults) {
    HUD.showForDuration("No matches for '" + findModeQuery.rawQuery + "'", 1000);
    return;
  }

  // if we have found an input element via 'n', pressing <esc> immediately afterwards sends us into insert
  // mode
  var elementCanTakeInput = domUtils.isSelectable(document.activeElement) &&
    isDOMDescendant(findModeAnchorNode, document.activeElement);
  if (elementCanTakeInput) {
    handlerStack.push({
      keydown: function(event) {
        handlerStack.pop();
        if (isEscape(event)) {
          domUtils.simulateSelect(document.activeElement);
          enterInsertModeWithoutShowingIndicator(document.activeElement);
          return false; // we have 'consumed' this event, so do not propagate
        }
        return true;
      }
    });
  }

  focusFoundLink();
}

function performFind() { findAndFocus(); }

function performBackwardsFind() { findAndFocus(true); }

function getLinkFromSelection() {
  var node = window.getSelection().anchorNode;
  while (node && node !== document.body) {
    if (node.nodeName.toLowerCase() === 'a') return node;
    node = node.parentNode;
  }
  return null;
}

// used by the findAndFollow* functions.
function followLink(linkElement) {
  if (linkElement.nodeName.toLowerCase() === 'link')
    window.location.href = linkElement.href;
  else {
    // if we can click on it, don't simply set location.href: some next/prev links are meant to trigger AJAX
    // calls, like the 'more' button on GitHub's newsfeed.
    linkElement.scrollIntoView();
    linkElement.focus();
    domUtils.simulateClick(linkElement);
  }
}

/**
 * Find and follow a link which matches any one of a list of strings. If there are multiple such links, they
 * are prioritized for shortness, by their position in :linkStrings, how far down the page they are located,
 * and finally by whether the match is exact. Practically speaking, this means we favor 'next page' over 'the
 * next big thing', and 'more' over 'nextcompany', even if 'next' occurs before 'more' in :linkStrings.
 */
function findAndFollowLink(linkStrings) {
  var linksXPath = domUtils.makeXPath(["a", "*[@onclick or @role='link' or contains(@class, 'button')]"]);
  var links = domUtils.evaluateXPath(linksXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE);
  var candidateLinks = [];

  // at the end of this loop, candidateLinks will contain all visible links that match our patterns
  // links lower in the page are more likely to be the ones we want, so we loop through the snapshot backwards
  for (var i = links.snapshotLength - 1; i >= 0; i--) {
    var link = links.snapshotItem(i);

    // ensure link is visible (we don't mind if it is scrolled offscreen)
    var boundingClientRect = link.getBoundingClientRect();
    if (boundingClientRect.width == 0 || boundingClientRect.height == 0)
      continue;
    var computedStyle = window.getComputedStyle(link, null);
    if (computedStyle.getPropertyValue('visibility') != 'visible' ||
        computedStyle.getPropertyValue('display') == 'none')
      continue;

    var linkMatches = false;
    for (var j = 0; j < linkStrings.length; j++) {
      if (link.innerText.toLowerCase().indexOf(linkStrings[j]) !== -1) {
        linkMatches = true;
        break;
      }
    }
    if (!linkMatches) continue;

    candidateLinks.push(link);
  }

  if (candidateLinks.length === 0) return;

  function wordCount(link) { return link.innerText.trim().split(/\s+/).length; }

  // We can use this trick to ensure that Array.sort is stable. We need this property to retain the reverse
  // in-page order of the links.
  candidateLinks.forEach(function(a,i){ a.originalIndex = i; });

  // favor shorter links, and ignore those that are more than one word longer than the shortest link
  candidateLinks =
    candidateLinks
      .sort(function(a,b) {
        var wcA = wordCount(a), wcB = wordCount(b);
        return wcA === wcB ? a.originalIndex - b.originalIndex : wcA - wcB;
      })
      .filter(function(a){return wordCount(a) <= wordCount(candidateLinks[0]) + 1});

  // try to get exact word matches first
  for (var i = 0; i < linkStrings.length; i++)
    for (var j = 0; j < candidateLinks.length; j++) {
      var exactWordRegex = new RegExp("\\b" + linkStrings[i] + "\\b", "i");
      if (exactWordRegex.test(candidateLinks[j].innerText)) {
        followLink(candidateLinks[j]);
        return true;
      }
    }

  for (var i = 0; i < linkStrings.length; i++)
    for (var j = 0; j < candidateLinks.length; j++) {
      if (candidateLinks[j].innerText.toLowerCase().indexOf(linkStrings[i]) !== -1) {
        followLink(candidateLinks[j]);
        return true;
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
        followLink(elements[j]);
        return true;
      }
    }
  }
}

function goPrevious() {
  var previousPatterns = settings.get("previousPatterns") || "";
  var previousStrings = previousPatterns.split(",");
  findAndFollowRel('prev') || findAndFollowLink(previousStrings);
}

function goNext() {
  var nextPatterns = settings.get("nextPatterns") || "";
  var nextStrings = nextPatterns.split(",");
  findAndFollowRel('next') || findAndFollowLink(nextStrings);
}

function showFindModeHUDForQuery() {
  if (findModeQueryHasResults || findModeQuery.parsedQuery.length == 0)
    HUD.show("/" + findModeQuery.rawQuery);
  else
    HUD.show("/" + findModeQuery.rawQuery + " (No Matches)");
}

function enterFindMode() {
  findModeQuery = { rawQuery: "" };
  findMode = true;
  HUD.show("/");
}

function exitFindMode() {
  findMode = false;
  HUD.hide();
}

function showHelpDialog(html, fid) {
  if (isShowingHelpDialog || !document.body || fid != frameId)
    return;
  isShowingHelpDialog = true;
  var container = document.createElement("div");
  container.id = "vimiumHelpDialogContainer";
  container.className = "vimiumReset";

  document.body.appendChild(container);

  container.innerHTML = html;
  container.getElementsByClassName("closeButton")[0].addEventListener("click", hideHelpDialog, false);
  container.getElementsByClassName("optionsPage")[0].addEventListener("click",
      function() { chrome.extension.sendRequest({ handler: "openOptionsPageInNewTab" }); }, false);

  // This is necessary because innerHTML does not evaluate javascript embedded in <script> tags.
  var scripts = Array.prototype.slice.call(container.getElementsByTagName("script"));
  scripts.forEach(function(script) { eval(script.text); });

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

  showForDuration: function(text, duration) {
    HUD.show(text);
    HUD._showForDurationTimerId = setTimeout(function() { HUD.hide(); }, duration);
  },

  show: function(text) {
    if (!HUD.enabled()) return;
    clearTimeout(HUD._showForDurationTimerId);
    HUD.displayElement().innerHTML = text;
    clearInterval(HUD._tweenId);
    HUD._tweenId = Tween.fade(HUD.displayElement(), 1.0, 150);
    HUD.displayElement().style.display = "";
  },

  showUpgradeNotification: function(version) {
    HUD.upgradeNotificationElement().innerHTML = "Vimium has been updated to " +
      "<a class='vimiumReset' href='https://chrome.google.com/extensions/detail/dbepggeogbaibhgnhhndojpepiihcmeb'>" +
      version + "</a>.<a class='vimiumReset close-button' href='#'>x</a>";
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

  /*
   * Retrieves the HUD HTML element.
   */
  displayElement: function() {
    if (!HUD._displayElement) {
      HUD._displayElement = HUD.createHudElement();
      // Keep this far enough to the right so that it doesn't collide with the "popups blocked" chrome HUD.
      HUD._displayElement.style.right = "150px";
    }
    return HUD._displayElement;
  },

  upgradeNotificationElement: function() {
    if (!HUD._upgradeNotificationElement) {
      HUD._upgradeNotificationElement = HUD.createHudElement();
      // Position this just to the left of our normal HUD.
      HUD._upgradeNotificationElement.style.right = "315px";
    }
    return HUD._upgradeNotificationElement;
  },

  createHudElement: function() {
    var element = document.createElement("div");
    element.className = "vimiumReset vimiumHUD";
    document.body.appendChild(element);
    return element;
  },

  hide: function(immediate) {
    clearInterval(HUD._tweenId);
    if (immediate)
      HUD.displayElement().style.display = "none";
    else
      HUD._tweenId = Tween.fade(HUD.displayElement(), 0, 150,
        function() { HUD.displayElement().style.display = "none"; });
  },

  isReady: function() { return document.body != null; },

  /* A preference which can be toggled in the Options page. */
  enabled: function() { return !settings.get("hideHud"); }

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
function addCssToPage(css, id) {
  var head = document.getElementsByTagName("head")[0];
  if (!head) {
    head = document.createElement("head");
    document.documentElement.appendChild(head);
  }
  var style = document.createElement("style");
  style.id = id;
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
