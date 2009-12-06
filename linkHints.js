/*
 * This implements link hinting. Typing "F" will enter link-hinting mode, where all clickable items on
 * the page have a hint marker displayed containing a sequence of letters. Typing those letters will select
 * a link.
 */
var linkHintsCss =
  '.vimiumHintMarker {' +
    'background-color:yellow;' +
    'color:black;' +
    'font-weight:bold;' +
    'font-size:12px;' +
    'padding:0 1px;' +
    'line-height:100%;' +
    'width:auto;' +
    'display:block;' +
    'border:1px solid #E3BE23;' +
    'z-index:99999999;' +
    'font-family:"Helvetica Neue", "Helvetica", "Arial", "Sans";' +
  '}' +
  '.vimiumHintMarker > span.matchingCharacter {' +
    'color:#C79F0B;' +
  '}';

var hintMarkers = [];
var hintCharacters = "sadfjkluewcm";
// The characters that were typed in while in "link hints" mode.
var hintKeystrokeQueue = [];
var linkHintsModeActivated = false;
var shouldOpenLinkHintInNewTab = false;
// Whether we have added to the page the CSS needed to display link hints.
var linkHintsCssAdded = false;

// An XPath describing what a clickable element is. We could also look for images with an onclick
// attribute, but let's wait to see if that really is necessary.
var clickableElementsXPath = "//a | //textarea | //button | //select | //input[not(@type='hidden')]";

// We need this as a top-level function because our command system doesn't yet support arguments.
function activateLinkHintsModeToOpenInNewTab() { activateLinkHintsMode(true); }

function activateLinkHintsMode(openInNewTab) {
  if (!linkHintsCssAdded)
    addCssToPage(linkHintsCss);
  linkHintsModeActivated = true;
  shouldOpenLinkHintInNewTab = openInNewTab
  buildLinkHints();
  document.addEventListener("keydown", onKeyDownInLinkHintsMode, true);
}

/*
 * Builds and displays link hints for every visible clickable item on the page.
 */
function buildLinkHints() {
  var visibleElements = getVisibleClickableElements();

  // Initialize the number used to generate the character hints to be as many digits as we need to
  // highlight all the links on the page; we don't want some link hints to have more chars than others.
  var digitsNeeded = Math.ceil(logXOfBase(visibleElements.length, hintCharacters.length));
  var linkHintNumber = 0;
  for (var i = 0; i < visibleElements.length; i++) {
    hintMarkers.push(addMarkerFor(visibleElements[i], linkHintNumber, digitsNeeded));
    linkHintNumber++;
  }
}

function logXOfBase(x, base) { return Math.log(x) / Math.log(base); }

/*
 * Returns all clickable elements that are not hidden and are in the current viewport.
 * We prune invisible elements partly for performance reasons, but moreso it's to decrease the number
 * of digits needed to enumerate all of the links on screen.
 */
function getVisibleClickableElements() {
  var resultSet = document.evaluate(clickableElementsXPath, document.body, null,
    XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
  var visibleElements = [];

  // Prune all invisible clickable elements.
  for (var i = 0; i < resultSet.snapshotLength; i++) {
    var element = resultSet.snapshotItem(i);

    // Note that getBoundingClientRect() is relative to the viewport
    var boundingRect = element.getBoundingClientRect();
    if (boundingRect.bottom < 0 || boundingRect.top > window.innerHeight)
      continue;

    // Using getElementFromPoint will omit elements which have visibility=hidden or display=none, and
    // elements inside of containers that are also hidden. We're checking for whether the element occupies
    // the upper left corner and if that fails, we also check whether the element occupies the center of the
    // box. We use the center of the box because it's more accurate when inline links have vertical padding,
    // like in the links ("Source", "Commits") at the top of github.com.
    // This will not exclude links with "opacity=0", like the links on Google's homepage (see bug #16).
    if (!elementOccupiesPoint(element, boundingRect.left, boundingRect.top)) {
      var elementOccupiesCenter = elementOccupiesPoint(element, boundingRect.left + boundingRect.width / 2,
          boundingRect.top + boundingRect.height / 2);
      if (!elementOccupiesCenter)
        continue;
    }

    visibleElements.push(element);
  }
  return visibleElements;
}

/*
 * Checks whether the clickable element or one of its descendents is at the given point. We must check
 * descendents because some clickable elements like "<a>" can have many nested children.
 */
function elementOccupiesPoint(clickableElement, x, y) {
  var elementAtPoint = getElementFromPoint(x, y);
  // Recurse up to 5 parents.
  for (var i = 0; i < 5 && elementAtPoint; i++) {
    if (elementAtPoint == clickableElement)
      return true;
    elementAtPoint = elementAtPoint.parentNode;
  }
  return false;
}
/*
 * Returns the element at the given point and factors in the page's CSS zoom level, which Webkit neglects
 * to do. This should become unnecessary when webkit fixes their bug.
 */
function getElementFromPoint(x, y) {
  var zoomFactor = currentZoomLevel / 100.0;
  return document.elementFromPoint(Math.ceil(x * zoomFactor), Math.ceil(y * zoomFactor));
}

function onKeyDownInLinkHintsMode(event) {
  var keyChar = String.fromCharCode(event.keyCode).toLowerCase();
  if (!keyChar)
    return;

  // TODO(philc): Ignore keys that have modifiers.
  if (event.keyCode == keyCodes.ESC) {
    deactivateLinkHintsMode();
  } else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
    if (hintKeystrokeQueue.length == 0) {
      deactivateLinkHintsMode();
    } else {
      hintKeystrokeQueue.pop();
      updateLinkHints();
    }
  } else if (hintCharacters.indexOf(keyChar) >= 0) {
    hintKeystrokeQueue.push(keyChar);
    updateLinkHints();
  } else {
    return;
  }

  event.stopPropagation();
  event.preventDefault();
}

/*
 * Updates the visibility of link hints on screen based on the keystrokes typed thus far. If only one
 * link hint remains, click on that link and exit link hints mode.
 */
function updateLinkHints() {
  var matchString = hintKeystrokeQueue.join("");
  var linksMatched = highlightLinkMatches(matchString);
  if (linksMatched.length == 0)
    deactivateLinkHintsMode();
  else if (linksMatched.length == 1) {
    var matchedLink = linksMatched[0];
    if (isInputOrText(matchedLink)) {
      matchedLink.focus();
      matchedLink.setSelectionRange(matchedLink.value.length, matchedLink.value.length);
    } else {
      // When we're opening the link in the current tab, don't navigate to the selected link immediately;
      // we want to give the user some feedback depicting which link they've selected by focusing it.
      if (!shouldOpenLinkHintInNewTab)
        setTimeout(function() { simulateClick(matchedLink); }, 400);
      else
        simulateClick(matchedLink);
      matchedLink.focus();
    }
    deactivateLinkHintsMode();
  }
}

/*
 * Hides link hints which do not match the given search string. To allow the backspace key to work, this
 * will also show link hints which do match but were previously hidden.
 */
function highlightLinkMatches(searchString) {
  var linksMatched = [];
  for (var i = 0; i < hintMarkers.length; i++) {
    var linkMarker = hintMarkers[i];
    if (linkMarker.getAttribute("hintString").indexOf(searchString) == 0) {
      if (linkMarker.style.display == "none")
        linkMarker.style.display = "";
      for (var j = 0; j < linkMarker.childNodes.length; j++)
        linkMarker.childNodes[j].className = (j >= searchString.length) ? "" : "matchingCharacter";
      linksMatched.push(linkMarker.clickableItem);
    } else {
      linkMarker.style.display = "none";
    }
  }
  return linksMatched;
}

/*
 * Converts a number like "8" into a hint string like "JK". This is used to sequentially generate all of
 * the hint text. The hint string will be "padded with zeroes" to ensure its length is equal to numHintDigits.
 */
function numberToHintString(number, numHintDigits) {
  var base = hintCharacters.length;
  var hintString = [];
  var remainder = 0;
  do {
    remainder = number % base;
    hintString.unshift(hintCharacters[remainder]);
    number -= remainder;
    number /= Math.floor(base);
  } while (number > 0);

  // Pad the hint string we're returning so that it matches numHintDigits.
  var hintStringLength = hintString.length;
  for (var i = 0; i < numHintDigits - hintStringLength; i++)
    hintString.unshift(hintCharacters[0]);
  return hintString.join("");
}

function simulateClick(link) {
  var event = document.createEvent("MouseEvents");
  // When "clicking" on a link, dispatch the event with the meta key on Mac to open it in a new tab.
  // TODO(philc): We should dispatch this event with CTRL down on Windows and Linux.
  event.initMouseEvent("click", true, true, window, 1, 0, 0, 0, 0, false, false, false,
      shouldOpenLinkHintInNewTab, 0, null);
  // Debugging note: Firefox will not execute the link's default action if we dispatch this click event,
  // but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
  link.dispatchEvent(event);
}

function deactivateLinkHintsMode() {
  for (var i = 0; i < hintMarkers.length; i++)
    hintMarkers[i].parentNode.removeChild(hintMarkers[i]);
  hintMarkers = [];
  hintKeystrokeQueue = [];
  document.removeEventListener("keydown", onKeyDownInLinkHintsMode, true);
  linkHintsModeActivated = false;
}

/*
 * Adds a link marker for the given link by adding a new element to <body> and positioning it on top of
 * the link.
 */
function addMarkerFor(link, linkHintNumber, linkHintDigits) {
  var hintString = numberToHintString(linkHintNumber, linkHintDigits);
  var marker = document.createElement("div");
  marker.className = "vimiumHintMarker";
  var innerHTML = [];
  // Make each hint character a span, so that we can highlight the typed characters as you type them.
  for (var i = 0; i < hintString.length; i++)
    innerHTML.push("<span>" + hintString[i].toUpperCase() + "</span>");
  marker.innerHTML = innerHTML.join("");
  marker.setAttribute("hintString", hintString);
  marker.style.position = "absolute";

  var boundingRect = link.getBoundingClientRect();
  // The coordinates given by the window do not have the zoom factor included since the zoom is set only on
  // the document node.
  var zoomFactor = currentZoomLevel / 100.0;
  marker.style.left = boundingRect.left + window.scrollX / zoomFactor + "px";
  marker.style.top = boundingRect.top  + window.scrollY / zoomFactor + "px";

  marker.clickableItem = link;
  // Note(philc): Append these markers to document.body instead of as child nodes to the link itself,
  // because some clickable elements cannot contain children, e.g. submit buttons. This has the caveat
  // that if you scroll the page and the link has position=fixed, the marker will not stay fixed.
  document.body.appendChild(marker);
  return marker;
}

/*
 * Adds the given CSS to the page. TODO: This may belong in the core vimium frontend.
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
