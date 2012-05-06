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
  shouldOpenInNewTab: false,
  shouldOpenWithQueue: false,
  // function that does the appropriate action on the selected link
  linkActivator: undefined,
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
    this.markerMatcher = settings.get('filterLinkHints') ? filterHints : alphabetHints;
  },

  /*
   * Generate an XPath describing what a clickable element is.
   * The final expression will be something like "//button | //xhtml:button | ..."
   * We use translate() instead of lower-case() because Chrome only supports XPath 1.0.
   */
  clickableElementsXPath: domUtils.makeXPath(["a", "area[@href]", "textarea", "button", "select",
                             "input[not(@type='hidden' or @disabled or @readonly)]",
                             "*[@onclick or @tabindex or @role='link' or @role='button' or contains(@class, 'button') or " +
                             "@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"]),

  // We need this as a top-level function because our command system doesn't yet support arguments.
  activateModeToOpenInNewTab: function() { this.activateMode(true, false, false); },

  activateModeToCopyLinkUrl: function() { this.activateMode(null, false, true); },

  activateModeWithQueue: function() { this.activateMode(true, true, false); },

  activateMode: function(openInNewTab, withQueue, copyLinkUrl) {
    if (!document.getElementById('vimiumLinkHintCss'))
      // linkHintCss is declared by vimiumFrontend.js and contains the user supplied css overrides.
      addCssToPage(linkHintCss, 'vimiumLinkHintCss');
    this.setOpenLinkMode(openInNewTab, withQueue, copyLinkUrl);
    this.buildLinkHints();
    handlerStack.push({ // handlerStack is declared by vimiumFrontend.js
      keydown: this.onKeyDownInMode,
      // trap all key events
      keypress: function() { return false; },
      keyup: function() { return false; }
    });
  },

  setOpenLinkMode: function(openInNewTab, withQueue, copyLinkUrl) {
    this.shouldOpenInNewTab = openInNewTab;
    this.shouldOpenWithQueue = withQueue;

    if (openInNewTab || withQueue) {
      if (openInNewTab)
        HUD.show("Open link in new tab");
      else if (withQueue)
        HUD.show("Open multiple links in a new tab");
      this.linkActivator = function(link) {
        // When "clicking" on a link, dispatch the event with the appropriate meta key (CMD on Mac, CTRL on windows)
        // to open it in a new tab if necessary.
        domUtils.simulateClick(link, { metaKey: platform == "Mac", ctrlKey: platform != "Mac" });
      }
    } else if (copyLinkUrl) {
      HUD.show("Copy link URL to Clipboard");
      this.linkActivator = function(link) {
        chrome.extension.sendRequest({handler: 'copyToClipboard', data: link.href});
      }
    } else {
      HUD.show("Open link in current tab");
      // When we're opening the link in the current tab, don't navigate to the selected link immediately;
      // we want to give the user some time to notice which link has received focus.
      this.linkActivator = function(link) {
        setTimeout(domUtils.simulateClick.bind(domUtils, link), 400);
      }
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
    this.hintMarkerContainingDiv.id = "vimiumHintMarkerContainer";
    this.hintMarkerContainingDiv.className = "vimiumReset";
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
    var resultSet = domUtils.evaluateXPath(this.clickableElementsXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE);

    var visibleElements = [];

    // Find all visible clickable elements.
    for (var i = 0, count = resultSet.snapshotLength; i < count; i++) {
      var element = resultSet.snapshotItem(i);
      var clientRect = domUtils.getVisibleClientRect(element, clientRect);
      if (clientRect !== null)
        visibleElements.push({element: element, rect: clientRect});

      if (element.localName === "area") {
        var map = element.parentElement;
        if (!map) continue;
        var img = document.querySelector("img[usemap='#" + map.getAttribute("name") + "']");
        if (!img) continue;
        var imgClientRects = img.getClientRects();
        if (imgClientRects.length == 0) continue;
        var c = element.coords.split(/,/);
        var coords = [parseInt(c[0], 10), parseInt(c[1], 10), parseInt(c[2], 10), parseInt(c[3], 10)];
        var rect = {
          top: imgClientRects[0].top + coords[1],
          left: imgClientRects[0].left + coords[0],
          right: imgClientRects[0].left + coords[2],
          bottom: imgClientRects[0].top + coords[3],
          width: coords[2] - coords[0],
          height: coords[3] - coords[1]
        };

        visibleElements.push({element: element, rect: rect});
      }
    }
    return visibleElements;
  },

  /*
   * Handles shift and esc keys. The other keys are passed to markerMatcher.matchHintsByKey.
   */
  onKeyDownInMode: function(event) {
    if (this.delayMode)
      return;

    if (event.keyCode == keyCodes.shiftKey && this.shouldOpenInNewTab !== null) {
      // Toggle whether to open link in a new or current tab.
      this.setOpenLinkMode(!this.shouldOpenInNewTab, this.shouldOpenWithQueue, false);
      handlerStack.push({
        keyup: function(event) {
          if (event.keyCode !== keyCodes.shiftKey) return;
          linkHints.setOpenLinkMode(!linkHints.shouldOpenInNewTab, linkHints.shouldOpenWithQueue, false);
          handlerStack.pop();
        }
      });
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
        this.activateLink(linksMatched[0], delay);
      } else {
        for (var i in this.hintMarkers)
          this.hideMarker(this.hintMarkers[i]);
        for (var i in linksMatched)
          this.showMarker(linksMatched[i], this.markerMatcher.hintKeystrokeQueue.length);
      }
    }
  },

  /*
   * When only one link hint remains, this function activates it in the appropriate way.
   */
  activateLink: function(matchedLink, delay) {
    this.delayMode = true;
    var clickEl = matchedLink.clickableItem;
    if (domUtils.isSelectable(clickEl)) {
      domUtils.simulateSelect(clickEl);
      this.deactivateMode(delay, function() { linkHints.delayMode = false; });
    } else {
      // TODO figure out which other input elements should not receive focus
      if (clickEl.nodeName.toLowerCase() === 'input' && clickEl.type !== 'button')
        clickEl.focus();
      domUtils.flashRect(matchedLink.rect);
      this.linkActivator(clickEl);
      if (this.shouldOpenWithQueue) {
        this.deactivateMode(delay, function() {
          linkHints.delayMode = false;
          linkHints.activateModeWithQueue();
        });
      } else {
        this.deactivateMode(delay, function() { linkHints.delayMode = false; });
      }
    }
  },

  /*
   * Shows the marker, highlighting matchingCharCount characters.
   */
  showMarker: function(linkMarker, matchingCharCount) {
    linkMarker.style.display = "";
    for (var j = 0, count = linkMarker.childNodes.length; j < count; j++)
      (j < matchingCharCount) ? linkMarker.childNodes[j].classList.add("matchingCharacter") :
                                linkMarker.childNodes[j].classList.remove("matchingCharacter");
  },

  hideMarker: function(linkMarker) {
    linkMarker.style.display = "none";
  },

  /*
   * If called without arguments, it executes immediately.  Othewise, it
   * executes after 'delay' and invokes 'callback' when it is finished.
   */
  deactivateMode: function(delay, callback) {
    function deactivate() {
      if (linkHints.markerMatcher.deactivate)
        linkHints.markerMatcher.deactivate();
      if (linkHints.hintMarkerContainingDiv)
        linkHints.hintMarkerContainingDiv.parentNode.removeChild(linkHints.hintMarkerContainingDiv);
      linkHints.hintMarkerContainingDiv = null;
      linkHints.hintMarkers = [];
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
    var hintStrings = this.hintStrings(visibleElements.length);
    var hintMarkers = [];
    for (var i = 0, count = visibleElements.length; i < count; i++) {
      var marker = hintUtils.createMarkerFor(visibleElements[i]);
      marker.hintString = hintStrings[i];
      marker.innerHTML = hintUtils.spanWrap(marker.hintString.toUpperCase());
      hintMarkers.push(marker);
    }

    return hintMarkers;
  },

  /*
   * Returns a list of hint strings which will uniquely identify the given number of links. The hint strings
   * may be of different lengths.
   */
  hintStrings: function(linkCount) {
    var linkHintCharacters = settings.get("linkHintCharacters");
    // Determine how many digits the link hints will require in the worst case. Usually we do not need
    // all of these digits for every link single hint, so we can show shorter hints for a few of the links.
    var digitsNeeded = Math.ceil(this.logXOfBase(linkCount, linkHintCharacters.length));
    // Short hints are the number of hints we can possibly show which are (digitsNeeded - 1) digits in length.
    var shortHintCount = Math.floor(
        (Math.pow(linkHintCharacters.length, digitsNeeded) - linkCount) /
        linkHintCharacters.length);
    var longHintCount = linkCount - shortHintCount;

    var hintStrings = [];

    if (digitsNeeded > 1)
      for (var i = 0; i < shortHintCount; i++)
        hintStrings.push(this.numberToHintString(i, digitsNeeded - 1, linkHintCharacters));

    var start = shortHintCount * linkHintCharacters.length;
    for (var i = start; i < start + longHintCount; i++)
      hintStrings.push(this.numberToHintString(i, digitsNeeded, linkHintCharacters));

    return this.shuffleHints(hintStrings, linkHintCharacters.length);
  },

  /*
   * This shuffles the given set of hints so that they're scattered -- hints starting with the same character
   * will be spread evenly throughout the array.
   */
  shuffleHints: function(hints, characterSetLength) {
    var buckets = [], i = 0;
    for (i = 0; i < characterSetLength; i++)
      buckets[i] = []
    for (i = 0; i < hints.length; i++)
      buckets[i % buckets.length].push(hints[i]);
    var result = [];
    for (i = 0; i < buckets.length; i++)
      result = result.concat(buckets[i]);
    return result;
  },

  /*
   * Converts a number like "8" into a hint string like "JK". This is used to sequentially generate all of
   * the hint text. The hint string will be "padded with zeroes" to ensure its length is equal to numHintDigits.
   */
  numberToHintString: function(number, numHintDigits, characterSet) {
    var base = characterSet.length;
    var hintString = [];
    var remainder = 0;
    do {
      remainder = number % base;
      hintString.unshift(characterSet[remainder]);
      number -= remainder;
      number /= Math.floor(base);
    } while (number > 0);

    // Pad the hint string we're returning so that it matches numHintDigits.
    // Note: the loop body changes hintString.length, so the original length must be cached!
    var hintStringLength = hintString.length;
    for (var i = 0; i < numHintDigits - hintStringLength; i++)
      hintString.unshift(characterSet[0]);

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
      return linkMarker.hintString.indexOf(matchString) == 0;
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

  generateHintString: function(linkHintNumber) {
    return (linkHintNumber + 1).toString();
  },

  generateLinkText: function(element) {
    var linkText = "";
    var showLinkText = false;
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
    return { text: linkText, show: showLinkText };
  },

  renderMarker: function(marker) {
    marker.innerHTML = hintUtils.spanWrap(marker.hintString +
                                          (marker.showLinkText ? ": " + marker.linkText : ""));
  },

  getHintMarkers: function(visibleElements) {
    this.generateLabelMap();
    var hintMarkers = [];
    for (var i = 0, count = visibleElements.length; i < count; i++) {
      var marker = hintUtils.createMarkerFor(visibleElements[i]);
      marker.hintString = this.generateHintString(i);
      var linkTextObject = this.generateLinkText(marker.clickableItem);
      marker.linkText = linkTextObject.text;
      marker.showLinkText = linkTextObject.show;
      this.renderMarker(marker);
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
      return !linkMarker.filtered && linkMarker.hintString.indexOf(matchString) == 0;
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
   * Marks the links that do not match the linkText search string with the 'filtered' DOM property. Renumbers
   * the remainder if necessary.
   */
  filterLinkHints: function(hintMarkers) {
    var linksMatched = [];
    var linkSearchString = this.linkTextKeystrokeQueue.join("");

    for (var i = 0; i < hintMarkers.length; i++) {
      var linkMarker = hintMarkers[i];
      var matchedLink = linkMarker.linkText.toLowerCase().indexOf(linkSearchString.toLowerCase()) >= 0;

      if (!matchedLink) {
        linkMarker.filtered = true;
      } else {
        linkMarker.filtered = false;
        var oldHintString = linkMarker.hintString;
        linkMarker.hintString = this.generateHintString(linksMatched.length);
        if (linkMarker.hintString != oldHintString)
          this.renderMarker(linkMarker);
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
      innerHTML.push("<span class='vimiumReset'>" + hintString[i] + "</span>");
    return innerHTML.join("");
  },

  /*
   * Creates a link marker for the given link.
   */
  createMarkerFor: function(link) {
    var marker = document.createElement("div");
    marker.className = "vimiumReset internalVimiumHintMarker vimiumHintMarker";
    marker.clickableItem = link.element;

    var clientRect = link.rect;
    marker.style.left = clientRect.left + window.scrollX + "px";
    marker.style.top = clientRect.top  + window.scrollY  + "px";

    marker.rect = link.rect;

    return marker;
  }
};
