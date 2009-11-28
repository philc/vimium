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
    'border:1px solid #E3BE23;' +
    'z-index:99999999;' +
    'font-family:"Helvetica Neue", "Helvetica", "Arial", "Sans";' +
  '}' +
  '.vimiumHintMarker > span.matchingCharacter {' +
    'color:#C79F0B;' +
  '}';

var hintMarkers = [];
var hintCharacters = "asdfjkl";
// The characters that were typed in while in "link hints" mode.
var hintKeystrokeQueue = [];
var linkHintsModeActivated = false;
// Whether we have added to the page the CSS needed to display link hints.
var linkHintsCssAdded = false;

// An XPath describing what a clickable element is. We could also look for images with an onclick
// attribute, but let's wait to see if that really is necessary.
var clickableElementsXPath = "//a | //textarea | //button | //select | //input[not(@type='hidden')]";

function activateLinkHintsMode() {
  if (!linkHintsCssAdded)
    addCssToPage(linkHintsCss);
  linkHintsModeActivated = true;
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
  var digitsNeeded = digitsNeededToRepresentLinks(visibleElements.length);
  var linkHintNumber = Math.pow(hintCharacters.length, digitsNeeded - 1);
  for (var i = 0; i < visibleElements.length; i++) {
    hintMarkers.push(addMarkerFor(visibleElements[i], linkHintNumber));
    linkHintNumber++;
  }
}

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
    // elements inside of containers that are also hidden.
    if (element != getElementFromPoint(boundingRect.left, boundingRect.top))
      continue;

    visibleElements.push(element);
  }
  return visibleElements;
}

/*
 * Returns the element at the given point and factors in the page's CSS zoom level, which Webkit neglects
 * to do. This should become unnecessary when webkit fixes their bug.
 */
function getElementFromPoint(x, y) {
  var zoomFactor = currentZoomLevel / 100.0;
  return document.elementFromPoint(Math.ceil(x * zoomFactor), Math.ceil(y * zoomFactor));
}

/*
 * Returns the number of digits that will be needed by the link hints to represent all of the elements
 * on screen. This assumes that we want all of the elements to have the same number of characters in
 * their link hints.
 */
function digitsNeededToRepresentLinks(numElements) {
  for (var i = 1; i < 5; i++) {
    var maxCharactersRepresented = Math.pow(hintCharacters.length, i);
    for (var j = 1; j < i; j++)
      maxCharactersRepresented -= Math.pow(hintCharacters.length, j);
    if (maxCharactersRepresented >= numElements)
      return i;
  }
  return 6;
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
    // Don't navigate to the selected link immediately; we want to give the user some feedback depicting
    // which link they've selected by focusing it. Note that for textareas and inputs, the click
    // event is ignored, but focus causes the desired behavior.
    setTimeout(function() { simulateClick(matchedLink); }, 600);
    matchedLink.focus();
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
 * the hint text.
 */
function numberToHintString(number) {
  var base = hintCharacters.length;
  var hintString = [];
  var remainder = 0;
  while (number > 0) {
    remainder = number % base;
    hintString.unshift(hintCharacters[remainder]);
    number -= remainder;
    number /= Math.floor(base);
  }
  return hintString.join("");
}

function simulateClick(link) {
  var event = document.createEvent("MouseEvents");
  event.initMouseEvent("click", true, true, window, 1, 0, 0, 0, 0, false, false, false, false, 0, null);
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
function addMarkerFor(link, linkHintNumber) {
  var hintString = numberToHintString(linkHintNumber);
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
