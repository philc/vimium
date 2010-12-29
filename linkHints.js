/*
 * This implements link hinting. Typing "F" will enter link-hinting mode, where all clickable items on
 * the page have a hint marker displayed containing a sequence of letters. Typing those letters will select
 * a link.
 *
 * The characters we use to show link hints are a user-configurable option. By default they're the home row.
 * The CSS which is used on the link hints is also a configurable option.
 */

var linkHints = {
  hintMarkers: [],
  hintMarkerContainingDiv: null,
  // The characters that were typed in while in "link hints" mode.
  hintKeystrokeQueue: [],
  linkTextKeystrokeQueue: [],
  linkHintsModeActivated: false,
  shouldOpenLinkHintInNewTab: false,
  shouldOpenLinkHintWithQueue: false,
  // Whether link hint's "open in current/new tab" setting is currently toggled 
  openLinkModeToggle: false,
  // Whether we have added to the page the CSS needed to display link hints.
  linkHintsCssAdded: false,

  /* 
   * Generate an XPath describing what a clickable element is.
   * The final expression will be something like "//button | //xhtml:button | ..."
   */
  clickableElementsXPath: (function() {
    var clickableElements = ["a", "textarea", "button", "select", "input[not(@type='hidden')]"];
    var xpath = [];
    for (var i in clickableElements)
      xpath.push("//" + clickableElements[i], "//xhtml:" + clickableElements[i]);
    xpath.push("//*[@onclick]");
    return xpath.join(" | ")
  })(),

  isNarrowMode: function () {
    return settings.narrowLinkHints == "true";
  },

  // We need this as a top-level function because our command system doesn't yet support arguments.
  activateLinkHintsModeToOpenInNewTab: function() { linkHints.activateLinkHintsMode(true, false); },

  activateLinkHintsModeWithQueue: function() { linkHints.activateLinkHintsMode(true, true); },

  activateLinkHintsMode: function (openInNewTab, withQueue) {
    if (!linkHints.linkHintsCssAdded)
      addCssToPage(linkHintCss); // linkHintCss is declared by vimiumFrontend.js
    linkHints.linkHintCssAdded = true;
    linkHints.linkHintsModeActivated = true;
    linkHints.setOpenLinkMode(openInNewTab, withQueue);
    linkHints.buildLinkHints();
    document.addEventListener("keydown", linkHints.onKeyDownInLinkHintsMode, true);
    document.addEventListener("keyup", linkHints.onKeyUpInLinkHintsMode, true);
  },

  setOpenLinkMode: function(openInNewTab, withQueue) {
    linkHints.shouldOpenLinkHintInNewTab = openInNewTab;
    linkHints.shouldOpenLinkHintWithQueue = withQueue;
    if (linkHints.shouldOpenLinkHintWithQueue) {
      HUD.show("Open multiple links in a new tab");
    } else {
      if (linkHints.shouldOpenLinkHintInNewTab)
        HUD.show("Open link in new tab");
      else
        HUD.show("Open link in current tab");
    }
  },

  /*
   * Builds and displays link hints for every visible clickable item on the page.
   */
  buildLinkHints: function() {
    var visibleElements = linkHints.getVisibleClickableElements();

    // Initialize the number used to generate the character hints to be as many digits as we need to
    // highlight all the links on the page; we don't want some link hints to have more chars than others.
    var digitsNeeded = Math.ceil(linkHints.logXOfBase(visibleElements.length, settings.linkHintCharacters.length));
    var linkHintNumber = 0;
    for (var i = 0; i < visibleElements.length; i++) {
      linkHints.hintMarkers.push(linkHints.createMarkerFor(visibleElements[i], linkHintNumber, digitsNeeded));
      linkHintNumber++;
    }
    // Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    // because some clickable elements cannot contain children, e.g. submit buttons. This has the caveat
    // that if you scroll the page and the link has position=fixed, the marker will not stay fixed.
    // Also note that adding these nodes to document.body all at once is significantly faster than one-by-one.
    linkHints.hintMarkerContainingDiv = document.createElement("div");
    linkHints.hintMarkerContainingDiv.className = "internalVimiumHintMarker";
    for (var i = 0; i < linkHints.hintMarkers.length; i++)
      linkHints.hintMarkerContainingDiv.appendChild(linkHints.hintMarkers[i]);
    document.body.appendChild(linkHints.hintMarkerContainingDiv);
  },

  logXOfBase: function(x, base) { return Math.log(x) / Math.log(base); },

  /*
   * Returns all clickable elements that are not hidden and are in the current viewport.
   * We prune invisible elements partly for performance reasons, but moreso it's to decrease the number
   * of digits needed to enumerate all of the links on screen.
   */
  getVisibleClickableElements: function() {
    var resultSet = document.evaluate(linkHints.clickableElementsXPath, document.body,
      function (namespace) {
        return namespace == "xhtml" ? "http://www.w3.org/1999/xhtml" : null;
      },
      XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);


    var visibleElements = [];

    // Find all visible clickable elements.
    for (var i = 0; i < resultSet.snapshotLength; i++) {
      var element = resultSet.snapshotItem(i);
      var clientRect = element.getClientRects()[0];

      if (linkHints.isVisible(element, clientRect))
        visibleElements.push({element: element, rect: clientRect});

      // If the link has zero dimensions, it may be wrapping visible
      // but floated elements. Check for this.
      if (clientRect && (clientRect.width == 0 || clientRect.height == 0)) {
        for (var j = 0; j < element.children.length; j++) {
          if (window.getComputedStyle(element.children[j], null).getPropertyValue('float') != 'none') {
            var childClientRect = element.children[j].getClientRects()[0];
            if (linkHints.isVisible(element.children[j], childClientRect)) {
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

  onKeyDownInLinkHintsMode: function(event) {
    console.log("Key Down");
    if (event.keyCode == keyCodes.shiftKey && !linkHints.openLinkModeToggle) {
      // Toggle whether to open link in a new or current tab.
      linkHints.setOpenLinkMode(!linkHints.shouldOpenLinkHintInNewTab, linkHints.shouldOpenLinkHintWithQueue);
      linkHints.openLinkModeToggle = true;
    }

    var keyChar = getKeyChar(event);
    if (!keyChar)
      return;

    // TODO(philc): Ignore keys that have modifiers.
    if (isEscape(event)) {
      linkHints.deactivateLinkHintsMode();
    } else {
      if (linkHints.isNarrowMode()) {
        if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
          if (linkHints.linkTextKeystrokeQueue.length == 0 && linkHints.hintKeystrokeQueue.length == 0) {
            linkHints.deactivateLinkHintsMode();
          } else {
            // backspace clears hint key queue first, then acts on link text key queue
            if (linkHints.hintKeystrokeQueue.pop() === undefined)
              linkHints.linkTextKeystrokeQueue.pop();
            linkHints.updateLinkHints();
          }
        } else if (/[0-9]/.test(keyChar)) {
          linkHints.hintKeystrokeQueue.push(keyChar);
          linkHints.updateLinkHints();
        } else {
          linkHints.linkTextKeystrokeQueue.push(keyChar);
          linkHints.updateLinkHints();
        }
      } else {
        if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
          if (linkHints.hintKeystrokeQueue.length == 0) {
            linkHints.deactivateLinkHintsMode();
          } else {
            linkHints.hintKeystrokeQueue.pop();
            linkHints.updateLinkHints();
          }
        } else if (settings.linkHintCharacters.indexOf(keyChar) >= 0) {
          linkHints.hintKeystrokeQueue.push(keyChar);
          linkHints.updateLinkHints();
        }
      }
    }

    event.stopPropagation();
    event.preventDefault();
  },

  onKeyUpInLinkHintsMode: function(event) {
    if (event.keyCode == keyCodes.shiftKey && linkHints.openLinkModeToggle) {
      // Revert toggle on whether to open link in new or current tab. 
      linkHints.setOpenLinkMode(!linkHints.shouldOpenLinkHintInNewTab, linkHints.shouldOpenLinkHintWithQueue);
      linkHints.openLinkModeToggle = false;
    }
    event.stopPropagation();
    event.preventDefault();
  },

  /*
   * Updates the visibility of link hints on screen based on the keystrokes typed thus far. If only one
   * link hint remains, click on that link and exit link hints mode.
   */
  updateLinkHints: function() {
    var matchString = linkHints.hintKeystrokeQueue.join("");
    var linksMatched = linkHints.highlightLinkMatches(matchString);
    if (linksMatched.length == 0)
      linkHints.deactivateLinkHintsMode();
    else if (linksMatched.length == 1) {
      var matchedLink = linksMatched[0];
      if (linkHints.isSelectable(matchedLink)) {
        matchedLink.focus();
        // When focusing a textbox, put the selection caret at the end of the textbox's contents.
        matchedLink.setSelectionRange(matchedLink.value.length, matchedLink.value.length);
        linkHints.deactivateLinkHintsMode();
      } else {
        // When we're opening the link in the current tab, don't navigate to the selected link immediately;
        // we want to give the user some feedback depicting which link they've selected by focusing it.
        if (linkHints.shouldOpenLinkHintWithQueue) {
          linkHints.simulateClick(matchedLink);
          linkHints.resetLinkHintsMode();
        } else if (linkHints.shouldOpenLinkHintInNewTab) {
          linkHints.simulateClick(matchedLink);
          matchedLink.focus();
          linkHints.deactivateLinkHintsMode();
        } else {
          setTimeout(function() { linkHints.simulateClick(matchedLink); }, 400);
          matchedLink.focus();
          linkHints.deactivateLinkHintsMode();
        }
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
   * Hides link hints which do not match the given search string. To allow the backspace key to work, this
   * will also show link hints which do match but were previously hidden.
   */
  highlightLinkMatches: function(searchString) {
    var linksMatched = [];
    var linkSearchString = linkHints.linkTextKeystrokeQueue.join("");
    var narrowMode = linkHints.isNarrowMode();
    var hasSearchString = searchString.length != 0;
    var hasLinkSearchString = linkSearchString.length != 0;
    var matchedCount = 0;

    for (var i = 0; i < linkHints.hintMarkers.length; i++) {
      var linkMarker = linkHints.hintMarkers[i];
      var matchedLink = linkMarker.getAttribute("linkText").toLowerCase().indexOf(linkSearchString.toLowerCase()) >= 0;
      var matchedHintStart = linkMarker.getAttribute("hintString").indexOf(searchString) == 0;

      var shouldRemoveMatch;
      if (narrowMode) {
        shouldRemoveMatch = 
          (!matchedLink && !matchedHintStart) || 
          (!matchedLink && hasLinkSearchString) ||
          (!matchedHintStart && hasSearchString)
      } else {
        shouldRemoveMatch = !matchedHintStart;
      }

      if (matchedHintStart) {
        for (var j = 0; j < linkMarker.childNodes.length; j++)
          linkMarker.childNodes[j].className = (j >= searchString.length) ? "" : "matchingCharacter";
      }

      if (shouldRemoveMatch) {
        linkMarker.style.display = "none";
      } else {
        if (linkMarker.style.display == "none")
          linkMarker.style.display = "";
        var newHint = matchedCount.toString();
        linkMarker.innerHTML = linkHints.spanWrap(newHint);
        linkMarker.setAttribute("hintString", newHint);
        linksMatched.push(linkMarker.clickableItem);
        matchedCount++;
      }

    }
    return linksMatched;
  },

  /*
   * Converts a number like "8" into a hint string like "JK". This is used to sequentially generate all of
   * the hint text. The hint string will be "padded with zeroes" to ensure its length is equal to numHintDigits.
   */
  numberToHintString: function(number, numHintDigits) {
    var base = settings.linkHintCharacters.length;
    var hintString = [];
    var remainder = 0;
    do {
      remainder = number % base;
      hintString.unshift(settings.linkHintCharacters[remainder]);
      number -= remainder;
      number /= Math.floor(base);
    } while (number > 0);

    // Pad the hint string we're returning so that it matches numHintDigits.
    var hintStringLength = hintString.length;
    for (var i = 0; i < numHintDigits - hintStringLength; i++)
      hintString.unshift(settings.linkHintCharacters[0]);
    return hintString.join("");
  },

  simulateClick: function(link) {
    var event = document.createEvent("MouseEvents");
    // When "clicking" on a link, dispatch the event with the appropriate meta key (CMD on Mac, CTRL on windows)
    // to open it in a new tab if necessary.
    var metaKey = (platform == "Mac" && linkHints.shouldOpenLinkHintInNewTab);
    var ctrlKey = (platform != "Mac" && linkHints.shouldOpenLinkHintInNewTab);
    event.initMouseEvent("click", true, true, window, 1, 0, 0, 0, 0, ctrlKey, false, false, metaKey, 0, null);

    // Debugging note: Firefox will not execute the link's default action if we dispatch this click event,
    // but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
    link.dispatchEvent(event);
  },

  deactivateLinkHintsMode: function() {
    if (linkHints.hintMarkerContainingDiv)
      linkHints.hintMarkerContainingDiv.parentNode.removeChild(linkHints.hintMarkerContainingDiv);
    linkHints.hintMarkerContainingDiv = null;
    linkHints.hintMarkers = [];
    linkHints.hintKeystrokeQueue = [];
    linkHints.linkTextKeystrokeQueue = [];
    document.removeEventListener("keydown", linkHints.onKeyDownInLinkHintsMode, true);
    document.removeEventListener("keyup", linkHints.onKeyUpInLinkHintsMode, true);
    linkHints.linkHintsModeActivated = false;
    HUD.hide();
  },

  resetLinkHintsMode: function() {
    linkHints.deactivateLinkHintsMode();
    linkHints.activateLinkHintsModeWithQueue();
  },

  /*
   * Creates a link marker for the given link.
   */
  createMarkerFor: function(link, linkHintNumber, linkHintDigits) {
    var hintString = linkHints.isNarrowMode() ?
      linkHintNumber.toString() : linkHints.numberToHintString(linkHintNumber, linkHintDigits);
    var linkText = link.element.innerHTML.toLowerCase();
    if (linkText == undefined) 
      linkText = "";
    var marker = document.createElement("div");
    marker.className = "internalVimiumHintMarker vimiumHintMarker";
    marker.innerHTML = linkHints.spanWrap(hintString);
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

  // Make each hint character a span, so that we can highlight the typed characters as you type them.
  spanWrap: function(hintString) {
    var innerHTML = [];
    for (var i = 0; i < hintString.length; i++)
      innerHTML.push("<span>" + hintString[i].toUpperCase() + "</span>");
    return innerHTML.join("");
  },
};
