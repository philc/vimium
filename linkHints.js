/*
 * This implements link hinting. Typing "F" will enter link-hinting mode, where all clickable items on the
 * page have a hint marker displayed containing a sequence of letters. Typing those letters will select a link.
 *
 * In our 'default' mode, the characters we use to show link hints are a user-configurable option. By default
 * they're the home row.  The CSS which is used on the link hints is also a configurable option.
 *
 * In 'filter' mode, our link hints are numbers, and the user can narrow down the range of possibilities by
 * typing the text of the link itself.
 */
var linkHints = {
  hintMarkers: [],
  hintMarkerContainingDiv: null,
  // The characters that were typed in while in "link hints" mode.
  shouldOpenInNewTab: false,
  shouldOpenWithQueue: false,
  // flag for copying link instead of opening
  shouldCopyLinkUrl: false,
  // Whether link hint's "open in current/new tab" setting is currently toggled
  openLinkModeToggle: false,
  // Whether we have added to the page the CSS needed to display link hints.
  cssAdded: false,
  // While in delayMode, all keypresses have no effect.
  delayMode: false,
  // Handle the link hinting marker generation and matching. Must be initialized after settings have been
  // loaded, so that we can retrieve the option setting.
  markerMatcher: undefined,

  /*
   * To be called after linkHints has been generated from linkHintsBase.
   */
  init: function() {
    this.onKeyDownInMode = this.onKeyDownInMode.bind(this);
    this.onKeyPressInMode = this.onKeyPressInMode.bind(this);
    this.onKeyUpInMode = this.onKeyUpInMode.bind(this);
    this.markerMatcher = settings.get('filterLinkHints') == "true" ? filterHints : alphabetHints;
  },

  /*
   * Generate an XPath describing what a clickable element is.
   * The final expression will be something like "//button | //xhtml:button | ..."
   * We use translate() instead of lower-case() because Chrome only supports XPath 1.0.
   */
  clickableElementsXPath: utils.makeXPath(["a", "area[@href]", "textarea", "button", "select","input[not(@type='hidden')]",
                             "*[@onclick or @tabindex or @role='link' or @role='button' or " +
                             "@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"]),

  // We need this as a top-level function because our command system doesn't yet support arguments.
  activateModeToOpenInNewTab: function() { this.activateMode(true, false, false); },

  activateModeToCopyLinkUrl: function() { this.activateMode(false, false, true); },

  activateModeWithQueue: function() { this.activateMode(true, true, false); },

  activateMode: function(openInNewTab, withQueue, copyLinkUrl) {
    if (!this.cssAdded)
      addCssToPage(linkHintCss); // linkHintCss is declared by vimiumFrontend.js
    this.linkHintCssAdded = true;
    this.setOpenLinkMode(openInNewTab, withQueue, copyLinkUrl);
    this.buildLinkHints();
    handlerStack.push({ // modeKeyHandler is declared by vimiumFrontend.js
      keydown: this.onKeyDownInMode,
      keypress: this.onKeyPressInMode,
      keyup: this.onKeyUpInMode
    });

    this.openLinkModeToggle = false;
  },

  setOpenLinkMode: function(openInNewTab, withQueue, copyLinkUrl) {
    this.shouldOpenInNewTab = openInNewTab;
    this.shouldOpenWithQueue = withQueue;
    this.shouldCopyLinkUrl = copyLinkUrl;
    if (this.shouldCopyLinkUrl) {
      HUD.show("Copy link URL to Clipboard");
    } else if (this.shouldOpenWithQueue) {
      HUD.show("Open multiple links in a new tab");
    } else {
      if (this.shouldOpenInNewTab)
        HUD.show("Open link in new tab");
      else
        HUD.show("Open link in current tab");
    }
  },

  /*
   * Builds and displays link hints for every visible clickable item on the page.
   */
  buildLinkHints: function() {
    var visibleElements = this.getVisibleClickableElements();
    this.hintMarkers = this.markerMatcher.getHintMarkers(visibleElements);

    // Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    // because some clickable elements cannot contain children, e.g. submit buttons. This has the caveat
    // that if you scroll the page and the link has position=fixed, the marker will not stay fixed.
    // Also note that adding these nodes to document.body all at once is significantly faster than one-by-one.
    this.hintMarkerContainingDiv = document.createElement("div");
    this.hintMarkerContainingDiv.className = "internalVimiumHintMarker";
    for (var i = 0; i < this.hintMarkers.length; i++)
      this.hintMarkerContainingDiv.appendChild(this.hintMarkers[i]);

    // sometimes this is triggered before documentElement is created
    // TODO(int3): fail more gracefully?
    if (document.documentElement)
      document.documentElement.appendChild(this.hintMarkerContainingDiv);
    else
      this.deactivateMode();
  },

  /*
   * Returns all clickable elements that are not hidden and are in the current viewport.
   * We prune invisible elements partly for performance reasons, but moreso it's to decrease the number
   * of digits needed to enumerate all of the links on screen.
   */
  getVisibleClickableElements: function() {
    var resultSet = utils.evaluateXPath(this.clickableElementsXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE);

    var visibleElements = [];

    // Find all visible clickable elements.
    for (var i = 0, count = resultSet.snapshotLength; i < count; i++) {
      var element = resultSet.snapshotItem(i);
      var clientRect = this.getVisibleClientRect(element, clientRect);
      if (clientRect !== null)
        visibleElements.push({element: element, rect: clientRect});

      if (element.localName === "area") {
        var map = element.parentElement;
        var img = document.querySelector("img[usemap='#" + map.getAttribute("name") + "']");
        var clientRect = img.getClientRects()[0];
        var c = element.coords.split(/,/);
        var coords = [parseInt(c[0], 10), parseInt(c[1], 10), parseInt(c[2], 10), parseInt(c[3], 10)];
        var rect = {
          top: clientRect.top + coords[1],
          left: clientRect.left + coords[0],
          right: clientRect.left + coords[2],
          bottom: clientRect.top + coords[3],
          width: coords[2] - coords[0],
          height: coords[3] - coords[1]
        };

        visibleElements.push({element: element, rect: rect});
      }
    }
    return visibleElements;
  },

  /**
   * Returns the first visible clientRect of an element if it exists. Otherwise it returns null.
   */
  getVisibleClientRect: function(element) {
    // Note: this call will be expensive if we modify the DOM in between calls.
    var clientRects = element.getClientRects();
    var clientRectsLength = clientRects.length;

    for (var i = 0; i < clientRectsLength; i++) {
      // Exclude links which have just a few pixels on screen, because the link hints won't show for them
      // anyway.
      if (clientRects[i].top < 0 || clientRects[i].top >= window.innerHeight - 4 ||
          clientRects[i].left < 0 || clientRects[i].left  >= window.innerWidth - 4)
        continue;

      if (clientRects[i].width < 3 || clientRects[i].height < 3)
        continue;

      // eliminate invisible elements (see test_harnesses/visibility_test.html)
      var computedStyle = window.getComputedStyle(element, null);
      if (computedStyle.getPropertyValue('visibility') != 'visible' ||
          computedStyle.getPropertyValue('display') == 'none')
        continue;

      return clientRects[i];
    }

    for (var i = 0; i < clientRectsLength; i++) {
      // If the link has zero dimensions, it may be wrapping visible
      // but floated elements. Check for this.
      if (clientRects[i].width == 0 || clientRects[i].height == 0) {
        for (var j = 0, childrenCount = element.children.length; j < childrenCount; j++) {
          var computedStyle = window.getComputedStyle(element.children[j], null);
          // Ignore child elements which are not floated and not absolutely positioned for parent elements with zero width/height
          if (computedStyle.getPropertyValue('float') == 'none' && computedStyle.getPropertyValue('position') != 'absolute')
            continue;
          var childClientRect = this.getVisibleClientRect(element.children[j]);
          if (childClientRect === null)
            continue;
          return childClientRect;
        }
      }
    };
    return null;
  },

  /*
   * Handles shift and esc keys. The other keys are passed to markerMatcher.matchHintsByKey.
   */
  onKeyDownInMode: function(event) {
    if (this.delayMode)
      return;

    if (event.keyCode == keyCodes.shiftKey && !this.openLinkModeToggle) {
      // Toggle whether to open link in a new or current tab.
      this.setOpenLinkMode(!this.shouldOpenInNewTab, this.shouldOpenWithQueue, false);
      this.openLinkModeToggle = true;
    }

    // TODO(philc): Ignore keys that have modifiers.
    if (isEscape(event)) {
      this.deactivateMode();
    } else {
      var keyResult = this.markerMatcher.matchHintsByKey(event, this.hintMarkers);
      var linksMatched = keyResult.linksMatched;
      var delay = keyResult.delay !== undefined ? keyResult.delay : 0;
      if (linksMatched.length == 0) {
        this.deactivateMode();
      } else if (linksMatched.length == 1) {
        this.activateLink(linksMatched[0].clickableItem, delay);
      } else {
        for (var i in this.hintMarkers)
          this.hideMarker(this.hintMarkers[i]);
        for (var i in linksMatched)
          this.showMarker(linksMatched[i], this.markerMatcher.hintKeystrokeQueue.length);
      }
    }

    event.stopPropagation();
    event.preventDefault();
  },

  onKeyPressInMode: function(event) {
    return !this.delayMode;
  },

  onKeyUpInMode: function(event) {
    if (this.delayMode)
      return;

    if (event.keyCode == keyCodes.shiftKey && this.openLinkModeToggle) {
      // Revert toggle on whether to open link in new or current tab.
      this.setOpenLinkMode(!this.shouldOpenInNewTab, this.shouldOpenWithQueue, false);
      this.openLinkModeToggle = false;
    }
    event.stopPropagation();
    event.preventDefault();
  },

  /*
   * When only one link hint remains, this function activates it in the appropriate way.
   */
  activateLink: function(matchedLink, delay) {
    var that = this;
    this.delayMode = true;
    if (this.isSelectable(matchedLink)) {
      this.simulateSelect(matchedLink);
      this.deactivateMode(delay, function() { that.delayMode = false; });
    } else {
      if (this.shouldOpenWithQueue) {
        this.simulateClick(matchedLink);
        this.deactivateMode(delay, function() {
          that.delayMode = false;
          that.activateModeWithQueue();
        });
      } else if (this.shouldCopyLinkUrl) {
        this.copyLinkUrl(matchedLink);
        this.deactivateMode(delay, function() { that.delayMode = false; });
      } else if (this.shouldOpenInNewTab) {
        this.simulateClick(matchedLink);
        matchedLink.focus();
        this.deactivateMode(delay, function() { that.delayMode = false; });
      } else {
        // When we're opening the link in the current tab, don't navigate to the selected link immediately;
        // we want to give the user some feedback depicting which link they've selected by focusing it.
        setTimeout(this.simulateClick.bind(this, matchedLink), 400);
        matchedLink.focus();
        this.deactivateMode(delay, function() { that.delayMode = false; });
      }
    }
  },

  /*
   * Selectable means the element has a text caret; this is not the same as "focusable".
   */
  isSelectable: function(element) {
    var selectableTypes = ["search", "text", "password"];
    return (element.nodeName.toLowerCase() == "input" && selectableTypes.indexOf(element.type) >= 0) ||
        element.nodeName.toLowerCase() == "textarea";
  },

  copyLinkUrl: function(link) {
    chrome.extension.sendRequest({handler: 'copyLinkUrl', data: link.href});
  },

  simulateSelect: function(element) {
    element.focus();
    // When focusing a textbox, put the selection caret at the end of the textbox's contents.
    element.setSelectionRange(element.value.length, element.value.length);
  },

  /*
   * Shows the marker, highlighting matchingCharCount characters.
   */
  showMarker: function(linkMarker, matchingCharCount) {
    linkMarker.style.display = "";
    for (var j = 0, count = linkMarker.childNodes.length; j < count; j++)
      linkMarker.childNodes[j].className = (j >= matchingCharCount) ? "" : "matchingCharacter";
  },

  hideMarker: function(linkMarker) {
    linkMarker.style.display = "none";
  },

  simulateClick: function(link) {
    var event = document.createEvent("MouseEvents");
    // When "clicking" on a link, dispatch the event with the appropriate meta key (CMD on Mac, CTRL on windows)
    // to open it in a new tab if necessary.
    var metaKey = (platform == "Mac" && linkHints.shouldOpenInNewTab);
    var ctrlKey = (platform != "Mac" && linkHints.shouldOpenInNewTab);
    event.initMouseEvent("click", true, true, window, 1, 0, 0, 0, 0, ctrlKey, false, false, metaKey, 0, null);

    // Debugging note: Firefox will not execute the link's default action if we dispatch this click event,
    // but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
    link.dispatchEvent(event);

    // TODO(int3): do this for @role='link' and similar elements as well
    var nodeName = link.nodeName.toLowerCase();
    if (nodeName == 'a' || nodeName == 'button')
      link.blur();
  },

  /*
   * If called without arguments, it executes immediately.  Othewise, it
   * executes after 'delay' and invokes 'callback' when it is finished.
   */
  deactivateMode: function(delay, callback) {
    var that = this;
    function deactivate() {
      if (that.markerMatcher.deactivate)
        that.markerMatcher.deactivate();
      if (that.hintMarkerContainingDiv)
        that.hintMarkerContainingDiv.parentNode.removeChild(that.hintMarkerContainingDiv);
      that.hintMarkerContainingDiv = null;
      that.hintMarkers = [];
      handlerStack.pop();
      HUD.hide();
    }
    // we invoke the deactivate() function directly instead of using setTimeout(callback, 0) so that
    // deactivateMode can be tested synchronously
    if (!delay) {
      deactivate();
      if (callback) callback();
    } else {
      setTimeout(function() { deactivate(); if (callback) callback(); }, delay);
    }
  },

};

var alphabetHints = {
  hintKeystrokeQueue: [],
  logXOfBase: function(x, base) { return Math.log(x) / Math.log(base); },

  getHintMarkers: function(visibleElements) {
    //Initialize the number used to generate the character hints to be as many digits as we need to highlight
    //all the links on the page; we don't want some link hints to have more chars than others.
    var digitsNeeded = Math.ceil(this.logXOfBase(
          visibleElements.length, settings.get('linkHintCharacters').length));
    var hintMarkers = [];

    for (var i = 0, count = visibleElements.length; i < count; i++) {
      var hintString = this.numberToHintString(i, digitsNeeded);
      var marker = hintUtils.createMarkerFor(visibleElements[i]);
      marker.innerHTML = hintUtils.spanWrap(hintString);
      marker.setAttribute("hintString", hintString);
      hintMarkers.push(marker);
    }

    return hintMarkers;
  },
  /*
   * Converts a number like "8" into a hint string like "JK". This is used to sequentially generate all of
   * the hint text. The hint string will be "padded with zeroes" to ensure its length is equal to numHintDigits.
   */
  numberToHintString: function(number, numHintDigits) {
    var base = settings.get('linkHintCharacters').length;
    var hintString = [];
    var remainder = 0;
    do {
      remainder = number % base;
      hintString.unshift(settings.get('linkHintCharacters')[remainder]);
      number -= remainder;
      number /= Math.floor(base);
    } while (number > 0);

    // Pad the hint string we're returning so that it matches numHintDigits.
    // Note: the loop body changes hintString.length, so the original length must be cached!
    var hintStringLength = hintString.length;
    for (var i = 0; i < numHintDigits - hintStringLength; i++)
      hintString.unshift(settings.get('linkHintCharacters')[0]);

    // Reversing the hint string has the advantage of making the link hints
    // appear to spread out after the first key is hit. This is helpful on a
    // page that has http links that are close to each other where link hints
    // of 2 characters or more occlude each other.
    hintString.reverse();
    return hintString.join("");
  },

  matchHintsByKey: function(event, hintMarkers) {
    var keyChar = getKeyChar(event);

    if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
      if (!this.hintKeystrokeQueue.pop())
        return { linksMatched: [] };
    } else if (keyChar && settings.get('linkHintCharacters').indexOf(keyChar) >= 0) {
      this.hintKeystrokeQueue.push(keyChar);
    }

    var matchString = this.hintKeystrokeQueue.join("");
    var linksMatched = hintMarkers.filter(function(linkMarker) {
      return linkMarker.getAttribute("hintString").indexOf(matchString) == 0;
    });
    return { linksMatched: linksMatched };
  },

  deactivate: function() {
    this.hintKeystrokeQueue = [];
  }

};

var filterHints = {
  hintKeystrokeQueue: [],
  linkTextKeystrokeQueue: [],
  labelMap: {},

  /*
   * Generate a map of input element => label
   */
  generateLabelMap: function() {
    var labels = document.querySelectorAll("label");
    for (var i = 0, count = labels.length; i < count; i++) {
      var forElement = labels[i].getAttribute("for");
      if (forElement) {
        var labelText = labels[i].textContent.trim();
        // remove trailing : commonly found in labels
        if (labelText[labelText.length-1] == ":")
          labelText = labelText.substr(0, labelText.length-1);
        this.labelMap[forElement] = labelText;
      }
    }
  },

  setMarkerAttributes: function(marker, linkHintNumber) {
    var hintString = (linkHintNumber + 1).toString();
    var linkText = "";
    var showLinkText = false;
    var element = marker.clickableItem;
    // toLowerCase is necessary as html documents return 'IMG'
    // and xhtml documents return 'img'
    var nodeName = element.nodeName.toLowerCase();

    if (nodeName == "input") {
      if (this.labelMap[element.id]) {
        linkText = this.labelMap[element.id];
        showLinkText = true;
      } else if (element.type != "password") {
        linkText = element.value;
      }
      // check if there is an image embedded in the <a> tag
    } else if (nodeName == "a" && !element.textContent.trim()
        && element.firstElementChild
        && element.firstElementChild.nodeName.toLowerCase() == "img") {
      linkText = element.firstElementChild.alt || element.firstElementChild.title;
      if (linkText)
        showLinkText = true;
    } else {
      linkText = element.textContent || element.innerHTML;
    }
    linkText = linkText.trim().toLowerCase();
    marker.setAttribute("hintString", hintString);
    marker.innerHTML = hintUtils.spanWrap(hintString + (showLinkText ? ": " + linkText : ""));
    marker.setAttribute("linkText", linkText);
  },

  getHintMarkers: function(visibleElements) {
    this.generateLabelMap();
    var hintMarkers = [];
    for (var i = 0, count = visibleElements.length; i < count; i++) {
      var marker = hintUtils.createMarkerFor(visibleElements[i]);
      this.setMarkerAttributes(marker, i);
      hintMarkers.push(marker);
    }
    return hintMarkers;
  },

  matchHintsByKey: function(event, hintMarkers) {
    var keyChar = getKeyChar(event);
    var delay = 0;
    var userIsTypingLinkText = false;

    if (event.keyCode == keyCodes.enter) {
      // activate the lowest-numbered link hint that is visible
      for (var i = 0, count = hintMarkers.length; i < count; i++)
        if (hintMarkers[i].style.display  != 'none') {
          return { linksMatched: [ hintMarkers[i] ] };
        }
    } else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
      // backspace clears hint key queue first, then acts on link text key queue.
      // if both queues are empty. exit hinting mode
      if (!this.hintKeystrokeQueue.pop() && !this.linkTextKeystrokeQueue.pop())
          return { linksMatched: [] };
    } else if (keyChar) {
      if (/[0-9]/.test(keyChar))
        this.hintKeystrokeQueue.push(keyChar);
      else {
        // since we might renumber the hints, the current hintKeyStrokeQueue
        // should be rendered invalid (i.e. reset).
        this.hintKeystrokeQueue = [];
        this.linkTextKeystrokeQueue.push(keyChar);
        userIsTypingLinkText = true;
      }
    }

    // at this point, linkTextKeystrokeQueue and hintKeystrokeQueue have been updated to reflect the latest
    // input. use them to filter the link hints accordingly.
    var linksMatched = this.filterLinkHints(hintMarkers);
    var matchString = this.hintKeystrokeQueue.join("");
    linksMatched = linksMatched.filter(function(linkMarker) {
      return linkMarker.getAttribute('filtered') != 'true'
        && linkMarker.getAttribute("hintString").indexOf(matchString) == 0;
    });

    if (linksMatched.length == 1 && userIsTypingLinkText) {
      // In filter mode, people tend to type out words past the point
      // needed for a unique match. Hence we should avoid passing
      // control back to command mode immediately after a match is found.
      var delay = 200;
    }

    return { linksMatched: linksMatched, delay: delay };
  },

  /*
   * Hides the links that do not match the linkText search string and marks them with the 'filtered' DOM
   * property. Renumbers the remainder.
   */
  filterLinkHints: function(hintMarkers) {
    var linksMatched = [];
    var linkSearchString = this.linkTextKeystrokeQueue.join("");

    for (var i = 0; i < hintMarkers.length; i++) {
      var linkMarker = hintMarkers[i];
      var matchedLink = linkMarker.getAttribute("linkText").toLowerCase()
                                  .indexOf(linkSearchString.toLowerCase()) >= 0;

      if (!matchedLink) {
        linkMarker.setAttribute("filtered", "true");
      } else {
        this.setMarkerAttributes(linkMarker, linksMatched.length);
        linkMarker.setAttribute("filtered", "false");
        linksMatched.push(linkMarker);
      }
    }
    return linksMatched;
  },

  deactivate: function(delay, callback) {
    this.hintKeystrokeQueue = [];
    this.linkTextKeystrokeQueue = [];
    this.labelMap = {};
  }

};

var hintUtils = {
  /*
   * Make each hint character a span, so that we can highlight the typed characters as you type them.
   */
  spanWrap: function(hintString) {
    var innerHTML = [];
    for (var i = 0; i < hintString.length; i++)
      innerHTML.push("<span>" + hintString[i].toUpperCase() + "</span>");
    return innerHTML.join("");
  },

  /*
   * Creates a link marker for the given link.
   */
  createMarkerFor: function(link) {
    var marker = document.createElement("div");
    marker.className = "internalVimiumHintMarker vimiumHintMarker";
    marker.clickableItem = link.element;

    var clientRect = link.rect;
    marker.style.left = clientRect.left + window.scrollX + "px";
    marker.style.top = clientRect.top  + window.scrollY  + "px";

    return marker;
  }
};
