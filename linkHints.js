/*
 * This implements link hinting. Typing "F" will enter link-hinting mode, where
 * all clickable items on the page have a hint marker displayed containing a
 * sequence of letters. Typing those letters will select a link.
 *
 * In our 'default' mode, the characters we use to show link hints are a
 * user-configurable option. By default they're the home row.  The CSS which is
 * used on the link hints is also a configurable option.
 *
 * In 'filter' mode, our link hints are numbers, and the user can narrow down
 * the range of possibilities by typing the text of the link itself.
 */

/*
 * A set of common operations shared by any link-hinting system. Some methods
 * are stubbed.
 */
var linkHintsPrototype = {
  hintMarkers: [],
  hintMarkerContainingDiv: null,
  // The characters that were typed in while in "link hints" mode.
  hintKeystrokeQueue: [],
  modeActivated: false,
  shouldOpenInNewTab: false,
  shouldOpenWithQueue: false,
  // Whether link hint's "open in current/new tab" setting is currently toggled 
  openLinkModeToggle: false,
  // Whether we have added to the page the CSS needed to display link hints.
  cssAdded: false,

  init: function() {
    // bind the event handlers to the appropriate instance of the prototype
    this.onKeyDownInMode = this.onKeyDownInMode.bind(this);
    this.onKeyUpInMode = this.onKeyUpInMode.bind(this);
  },

  /* 
   * Generate an XPath describing what a clickable element is.
   * The final expression will be something like "//button | //xhtml:button | ..."
   */
  clickableElementsXPath: (function() {
    var clickableElements = ["a", "textarea", "button", "select", "input[not(@type='hidden')]",
                             "*[@onclick or @tabindex or @role='link' or @role='button']"];
    var xpath = [];
    for (var i in clickableElements)
      xpath.push("//" + clickableElements[i], "//xhtml:" + clickableElements[i]);
    return xpath.join(" | ")
  })(),

  // We need this as a top-level function because our command system doesn't yet support arguments.
  activateModeToOpenInNewTab: function() { this.activateMode(true, false); },

  activateModeWithQueue: function() { this.activateMode(true, true); },

  activateMode: function (openInNewTab, withQueue) {
    if (!this.cssAdded)
      addCssToPage(linkHintCss); // linkHintCss is declared by vimiumFrontend.js
    this.linkHintCssAdded = true;
    this.modeActivated = true;
    this.setOpenLinkMode(openInNewTab, withQueue);
    this.buildLinkHints();
    document.addEventListener("keydown", this.onKeyDownInMode, true);
    document.addEventListener("keyup", this.onKeyUpInMode, true);
  },

  setOpenLinkMode: function(openInNewTab, withQueue) {
    this.shouldOpenInNewTab = openInNewTab;
    this.shouldOpenWithQueue = withQueue;
    if (this.shouldOpenWithQueue) {
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

    // Initialize the number used to generate the character hints to be as many digits as we need to
    // highlight all the links on the page; we don't want some link hints to have more chars than others.
    var linkHintNumber = 0;
    this.initHintStringGenerator(visibleElements);
    for (var i = 0; i < visibleElements.length; i++) {
      this.hintMarkers.push(this.createMarkerFor(
            visibleElements[i], linkHintNumber, this.hintStringGenerator.bind(this)));
      linkHintNumber++;
    }
    // Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    // because some clickable elements cannot contain children, e.g. submit buttons. This has the caveat
    // that if you scroll the page and the link has position=fixed, the marker will not stay fixed.
    // Also note that adding these nodes to document.body all at once is significantly faster than one-by-one.
    this.hintMarkerContainingDiv = document.createElement("div");
    this.hintMarkerContainingDiv.className = "internalVimiumHintMarker";
    for (var i = 0; i < this.hintMarkers.length; i++)
      this.hintMarkerContainingDiv.appendChild(this.hintMarkers[i]);
    document.documentElement.appendChild(this.hintMarkerContainingDiv);
  },

  /*
   * Takes a number and returns the string label for the hint.
   */ 
  hintStringGenerator: function(linkHintNumber) {},

  /*
   * A hook for any necessary initialization for hintStringGenerator.  Takes an
   * array of visible elements. Any return value is ignored.
   */
  initHintStringGenerator: function(visibleElements) {},

  /*
   * Returns all clickable elements that are not hidden and are in the current viewport.
   * We prune invisible elements partly for performance reasons, but moreso it's to decrease the number
   * of digits needed to enumerate all of the links on screen.
   */
  getVisibleClickableElements: function() {
    var resultSet = document.evaluate(this.clickableElementsXPath, document.body,
      function (namespace) {
        return namespace == "xhtml" ? "http://www.w3.org/1999/xhtml" : null;
      },
      XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);


    var visibleElements = [];

    // Find all visible clickable elements.
    for (var i = 0; i < resultSet.snapshotLength; i++) {
      var element = resultSet.snapshotItem(i);
      var clientRect = element.getClientRects()[0];

      if (this.isVisible(element, clientRect))
        visibleElements.push({element: element, rect: clientRect});

      // If the link has zero dimensions, it may be wrapping visible
      // but floated elements. Check for this.
      if (clientRect && (clientRect.width == 0 || clientRect.height == 0)) {
        for (var j = 0; j < element.children.length; j++) {
          if (window.getComputedStyle(element.children[j], null).getPropertyValue('float') != 'none') {
            var childClientRect = element.children[j].getClientRects()[0];
            if (this.isVisible(element.children[j], childClientRect)) {
              visibleElements.push({element: element.children[j], rect: childClientRect});
              break;
            }
          }
        }
      }
    }
    return visibleElements;
  },

  /*
   * Returns true if element is visible.
   */
  isVisible: function(element, clientRect) {
    // Exclude links which have just a few pixels on screen, because the link hints won't show for them anyway.
    var zoomFactor = currentZoomLevel / 100.0;
    if (!clientRect || clientRect.top < 0 || clientRect.top * zoomFactor >= window.innerHeight - 4 ||
        clientRect.left < 0 || clientRect.left * zoomFactor >= window.innerWidth - 4)
      return false;

    if (clientRect.width < 3 || clientRect.height < 3)
      return false;

    // eliminate invisible elements (see test_harnesses/visibility_test.html)
    var computedStyle = window.getComputedStyle(element, null);
    if (computedStyle.getPropertyValue('visibility') != 'visible' ||
        computedStyle.getPropertyValue('display') == 'none')
      return false;

    return true;
  },

  /*
   * Handles shift and esc keys. The other keys are passed to normalKeyDownHandler.
   */
  onKeyDownInMode: function(event) {
    console.log("Key Down");
    if (event.keyCode == keyCodes.shiftKey && !this.openLinkModeToggle) {
      // Toggle whether to open link in a new or current tab.
      this.setOpenLinkMode(!this.shouldOpenInNewTab, this.shouldOpenWithQueue);
      this.openLinkModeToggle = true;
    }

    // TODO(philc): Ignore keys that have modifiers.
    if (isEscape(event)) {
      this.deactivateMode();
    } else {
      this.normalKeyDownHandler(event);
    }

    event.stopPropagation();
    event.preventDefault();
  },

  /*
   * Handle all keys other than shift and esc. Return value is ignored.
   */
  normalKeyDownHandler: function(event) {},

  onKeyUpInMode: function(event) {
    if (event.keyCode == keyCodes.shiftKey && this.openLinkModeToggle) {
      // Revert toggle on whether to open link in new or current tab. 
      this.setOpenLinkMode(!this.shouldOpenInNewTab, this.shouldOpenWithQueue);
      this.openLinkModeToggle = false;
    }
    event.stopPropagation();
    event.preventDefault();
  },

  /*
   * When only one link hint remains, this function activates it in the appropriate way.
   */
  activateLink: function(matchedLink) {
    if (this.isSelectable(matchedLink)) {
      matchedLink.focus();
      // When focusing a textbox, put the selection caret at the end of the textbox's contents.
      matchedLink.setSelectionRange(matchedLink.value.length, matchedLink.value.length);
      this.deactivateMode();
    } else {
      // When we're opening the link in the current tab, don't navigate to the selected link immediately;
      // we want to give the user some feedback depicting which link they've selected by focusing it.
      if (this.shouldOpenWithQueue) {
        this.simulateClick(matchedLink);
        this.resetMode();
      } else if (this.shouldOpenInNewTab) {
        this.simulateClick(matchedLink);
        matchedLink.focus();
        this.deactivateMode();
      } else {
        setTimeout(this.simulateClick.bind(this, matchedLink), 400);
        matchedLink.focus();
        this.deactivateMode();
      }
    }
  },

  /*
   * Selectable means the element has a text caret; this is not the same as "focusable".
   */
  isSelectable: function(element) {
    var selectableTypes = ["search", "text", "password"];
    return (element.tagName == "INPUT" && selectableTypes.indexOf(element.type) >= 0) ||
        element.tagName == "TEXTAREA";
  },

  /*
   * Hides linkMarker if it does not match testString, and shows linkMarker
   * if it does match but was previously hidden. To be used with Array.filter().
   */
  toggleHighlights: function(testString, linkMarker) {
    if (linkMarker.getAttribute("hintString").indexOf(testString) == 0) {
      if (linkMarker.style.display == "none")
        linkMarker.style.display = "";
      for (var j = 0; j < linkMarker.childNodes.length; j++)
        linkMarker.childNodes[j].className = (j >= testString.length) ? "" : "matchingCharacter";
      return true;
    } else {
      linkMarker.style.display = "none";
      return false;
    }
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
  },

  deactivateMode: function() {
    if (this.hintMarkerContainingDiv)
      this.hintMarkerContainingDiv.parentNode.removeChild(this.hintMarkerContainingDiv);
    this.hintMarkerContainingDiv = null;
    this.hintMarkers = [];
    this.hintKeystrokeQueue = [];
    document.removeEventListener("keydown", this.onKeyDownInMode, true);
    document.removeEventListener("keyup", this.onKeyUpInMode, true);
    this.modeActivated = false;
    HUD.hide();
  },

  resetMode: function() {
    this.deactivateMode();
    this.activateModeWithQueue();
  },

  /*
   * Creates a link marker for the given link.
   */
  createMarkerFor: function(link, linkHintNumber, stringGenerator) {
    var hintString = stringGenerator(linkHintNumber);
    var linkText = link.element.innerHTML.toLowerCase();
    if (linkText == undefined) 
      linkText = "";
    var marker = document.createElement("div");
    marker.className = "internalVimiumHintMarker vimiumHintMarker";
    marker.innerHTML = this.spanWrap(hintString);
    marker.setAttribute("hintString", hintString);
    marker.setAttribute("linkText", linkText);

    // Note: this call will be expensive if we modify the DOM in between calls.
    var clientRect = link.rect;
    // The coordinates given by the window do not have the zoom factor included since the zoom is set only on
    // the document node.
    var zoomFactor = currentZoomLevel / 100.0;
    marker.style.left = clientRect.left + window.scrollX / zoomFactor + "px";
    marker.style.top = clientRect.top  + window.scrollY / zoomFactor + "px";

    marker.clickableItem = link.element;
    return marker;
  },

  /*
   * Make each hint character a span, so that we can highlight the typed characters as you type them.
   */
  spanWrap: function(hintString) {
    var innerHTML = [];
    for (var i = 0; i < hintString.length; i++)
      innerHTML.push("<span>" + hintString[i].toUpperCase() + "</span>");
    return innerHTML.join("");
  },

};

var linkHints;
/*
 * Create the instance of linkHints, specialized based on the user settings.
 */
function initializeLinkHints() {
  linkHints = Object.create(linkHintsPrototype);
  linkHints.init();

  if (settings.get('filterLinkHints') != "true") { // the default hinting system

    linkHints['digitsNeeded'] = 1;

    linkHints['logXOfBase'] = function(x, base) { return Math.log(x) / Math.log(base); };

    linkHints['initHintStringGenerator'] = function(visibleElements) {
      this.digitsNeeded = Math.ceil(this.logXOfBase(
            visibleElements.length, settings.get('linkHintCharacters').length));
    };

    linkHints['hintStringGenerator'] = function(linkHintNumber) {
      return this.numberToHintString(linkHintNumber, this.digitsNeeded);
    };

    /*
     * Converts a number like "8" into a hint string like "JK". This is used to sequentially generate all of
     * the hint text. The hint string will be "padded with zeroes" to ensure its length is equal to numHintDigits.
     */
    linkHints['numberToHintString'] = function(number, numHintDigits) {
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
      var hintStringLength = hintString.length;
      for (var i = 0; i < numHintDigits - hintStringLength; i++)
        hintString.unshift(settings.get('linkHintCharacters')[0]);
      return hintString.join("");
    };

    linkHints['normalKeyDownHandler'] = function (event) {
      var keyChar = getKeyChar(event);
      if (!keyChar)
        return;

      if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
        if (this.hintKeystrokeQueue.length == 0) {
          this.deactivateMode();
        } else {
          this.hintKeystrokeQueue.pop();
          var matchString = this.hintKeystrokeQueue.join("");
          this.hintMarkers.filter(this.toggleHighlights.bind(this, matchString));
        }
      } else if (settings.get('linkHintCharacters').indexOf(keyChar) >= 0) {
        this.hintKeystrokeQueue.push(keyChar);
        var matchString = this.hintKeystrokeQueue.join("");
        linksMatched = this.hintMarkers.filter(this.toggleHighlights.bind(this, matchString));
        if (linksMatched.length == 0)
          this.deactivateMode();
        else if (linksMatched.length == 1)
          this.activateLink(linksMatched[0].clickableItem);
      }
    };

  } else {

    linkHints['linkTextKeystrokeQueue'] = [];

    linkHints['hintStringGenerator'] = function(linkHintNumber) {
      return (linkHintNumber + 1).toString();
    };

    linkHints['normalKeyDownHandler'] = function(event) {
      if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
        if (this.linkTextKeystrokeQueue.length == 0 && this.hintKeystrokeQueue.length == 0) {
          this.deactivateMode();
        } else {
          // backspace clears hint key queue first, then acts on link text key queue
          if (this.hintKeystrokeQueue.pop())
            this.filterLinkHints();
          else {
            this.linkTextKeystrokeQueue.pop();
            this.filterLinkHints();
          }
        }
      } else {
        var keyChar = getKeyChar(event);
        if (!keyChar)
          return;

        var linksMatched, matchString;
        if (/[0-9]/.test(keyChar)) {
          this.hintKeystrokeQueue.push(keyChar);
          matchString = this.hintKeystrokeQueue.join("");
          linksMatched = this.hintMarkers.filter((function(linkMarker) {
            if (linkMarker.getAttribute('filtered') == 'true')
              return false;
            return this.toggleHighlights(matchString, linkMarker);
          }).bind(this));
        } else {
          // since we might renumber the hints, the current hintKeyStrokeQueue
          // should be rendered invalid (i.e. reset).
          this.hintKeystrokeQueue = [];
          this.linkTextKeystrokeQueue.push(keyChar);
          matchString = this.linkTextKeystrokeQueue.join("");
          linksMatched = this.filterLinkHints(matchString);
        }

        if (linksMatched.length == 0)
          this.deactivateMode();
        else if (linksMatched.length == 1)
          this.activateLink(linksMatched[0].clickableItem);
      }
    };

    /*
     * Hides the links that do not match the linkText search string and marks
     * them with the 'filtered' DOM property. Renumbers the remainder.  Should
     * only be called when there is a change in linkTextKeystrokeQueue, to
     * avoid undesired renumbering.
    */
    linkHints['filterLinkHints'] = function(searchString) {
      var linksMatched = [];
      var linkSearchString = this.linkTextKeystrokeQueue.join("");

      for (var i = 0; i < this.hintMarkers.length; i++) {
        var linkMarker = this.hintMarkers[i];
        var matchedLink = linkMarker.getAttribute("linkText").toLowerCase().indexOf(linkSearchString.toLowerCase()) >= 0;

        if (!matchedLink) {
          linkMarker.style.display = "none";
          linkMarker.setAttribute("filtered", "true");
        } else {
          if (linkMarker.style.display == "none")
            linkMarker.style.display = "";
          var newHintText = (linksMatched.length+1).toString();
          linkMarker.innerHTML = this.spanWrap(newHintText);
          linkMarker.setAttribute("hintString", newHintText);
          linkMarker.setAttribute("filtered", "false");
          linksMatched.push(linkMarker);
        }
      }
      return linksMatched;
    };

    linkHints['deactivateMode'] = function() {
      this.linkTextKeystrokeQueue = [];
      // call(this) is necessary to make deactivateMode reset
      // the variables in linkHints instead of linkHintsPrototype
      Object.getPrototypeOf(this).deactivateMode.call(this);
    };

  }
}
