// NOTE(smblott). Ultimately, all of the FindMode-related code should be moved here.

// This prevents unmapped printable characters from being passed through to underlying page; see
// #1415. Only used by PostFindMode, below.
class SuppressPrintable extends Mode {
  constructor(options) {
    super();
    super.init(options);
    const handler = (event) =>
      KeyboardUtils.isPrintable(event) ? this.suppressEvent : this.continueBubbling;
    const type = DomUtils.getSelectionType();

    // We use unshift here, so we see events after normal mode, so we only see unmapped keys.
    this.unshift({
      _name: `mode-${this.id}/suppress-printable`,
      keydown: handler,
      keypress: handler,
      keyup: () => {
        // If the selection type has changed (usually, no longer "Range"), then the user is
        // interacting with the input element, so we get out of the way. See discussion of option 5c
        // from #1415.
        if (DomUtils.getSelectionType() !== type) {
          return this.exit();
        }
      },
    });
  }
}

// When we use find, the selection/focus can land in a focusable/editable element. In this
// situation, special considerations apply. We implement three special cases:
//   1. Disable insert mode, because the user hasn't asked to enter insert mode. We do this by using
//      InsertMode.suppressEvent.
//   2. Prevent unmapped printable keyboard events from propagating to the page; see #1415. We do
//      this by inheriting from SuppressPrintable.
//   3. If the very-next keystroke is Escape, then drop immediately into insert mode.
//
const newPostFindMode = function () {
  if (!document.activeElement || !DomUtils.isEditable(document.activeElement)) {
    return;
  }
  return new PostFindMode();
};

class PostFindMode extends SuppressPrintable {
  constructor() {
    const element = document.activeElement;
    super({
      name: "post-find",
      // PostFindMode shares a singleton with focusInput; each displaces the other.
      singleton: "post-find-mode/focus-input",
      exitOnBlur: element,
      exitOnClick: true,
      // Always truthy, so always continues bubbling.
      keydown(event) {
        return InsertMode.suppressEvent(event);
      },
      keypress(event) {
        return InsertMode.suppressEvent(event);
      },
      keyup(event) {
        return InsertMode.suppressEvent(event);
      },
    });

    // If the very-next keydown is Escape, then exit immediately, thereby passing subsequent keys to
    // the underlying insert-mode instance.
    this.push({
      _name: `mode-${this.id}/handle-escape`,
      keydown: (event) => {
        if (KeyboardUtils.isEscape(event)) {
          this.exit();
          return this.suppressEvent;
        } else {
          handlerStack.remove();
          return this.continueBubbling;
        }
      },
    });
  }
}

class FindMode extends Mode {
  constructor(options) {
    super();

    if (options == null) {
      options = {};
    }

    this.query = {
      rawQuery: "",
      parsedQuery: "",
      matchCount: 0,
      hasResults: false,
    };

    // Save the selection, so findInPlace can restore it.
    this.initialRange = getCurrentRange();
    FindMode.query = { rawQuery: "" };

    if (options.returnToViewport) {
      this.scrollX = window.scrollX;
      this.scrollY = window.scrollY;
    }

    super.init(Object.assign(options, {
      name: "find",
      indicator: false,
      exitOnClick: true,
      exitOnEscape: true,
      // This prevents further Vimium commands launching before the find-mode HUD receives the
      // focus. E.g. "/" followed quickly by "i" should not leave us in insert mode.
      suppressAllKeyboardEvents: true,
    }));

    HUD.showFindMode(this);
  }

  exit(event) {
    HUD.unfocusIfFocused();
    super.exit();
    if (event) {
      FindMode.handleEscape();
    }
  }

  restoreSelection() {
    if (!this.initialRange) {
      return;
    }
    const range = this.initialRange;
    const selection = getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }

  findInPlace(query, options) {
    // If requested, restore the scroll position (so that failed searches leave the scroll position
    // unchanged).
    this.checkReturnToViewPort();
    FindMode.updateQuery(query);
    // Restore the selection. That way, we're always searching forward from the same place, so we
    // find the right match as the user adds matching characters, or removes previously-matched
    // characters. See #1434.
    this.restoreSelection();
    query = FindMode.query.isRegex
      ? FindMode.getQueryFromRegexMatches()
      : FindMode.query.parsedQuery;
    FindMode.query.hasResults = FindMode.execute(query, options);
  }

  static updateQuery(query) {
    let pattern;
    this.query.rawQuery = query;
    // the query can be treated differently (e.g. as a plain string versus regex depending on the
    // presence of escape sequences. '\' is the escape character and needs to be escaped itself to
    // be used as a normal character. here we grep for the relevant escape sequences.
    this.query.isRegex = Settings.get("regexFindMode");
    this.query.parsedQuery = this.query.rawQuery.replace(
      /(\\{1,2})([rRI]?)/g,
      (match, slashes, flag) => {
        if ((flag === "") || (slashes.length !== 1)) {
          return match;
        }

        switch (flag) {
          case "r":
            this.query.isRegex = true;
            break;
          case "R":
            this.query.isRegex = false;
            break;
        }
        return "";
      },
    );

    // Implement smartcase.
    this.query.ignoreCase = !Utils.hasUpperCase(this.query.parsedQuery);

    const regexPattern = this.query.isRegex
      ? this.query.parsedQuery
      : Utils.escapeRegexSpecialCharacters(this.query.parsedQuery);

    // Grep for all matches in every text node,
    // so we can show a the number of results.
    try {
      pattern = new RegExp(regexPattern, `g${this.query.ignoreCase ? "i" : ""}`);
    } catch {
      // If we catch a SyntaxError, assume the user is not done typing yet and return quietly.
      return;
    }

    const textNodes = getAllTextNodes();
    const matchedNodes = textNodes.filter((node) => {
      return node.textContent.match(pattern);
    });
    const regexMatches = matchedNodes.map((node) => node.textContent.match(pattern));
    this.query.regexMatches = regexMatches;
    this.query.regexPattern = pattern;
    this.query.regexMatchedNodes = matchedNodes;
    this.updateActiveRegexIndices();

    return this.query.matchCount = regexMatches != null ? regexMatches.flat().length : null;
  }

  // set activeRegexIndices near the latest selection
  static updateActiveRegexIndices() {
    let activeNodeIndex = -1;
    const matchedNodes = this.query.regexMatchedNodes;
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      activeNodeIndex = matchedNodes.indexOf(selection.anchorNode);

      if (activeNodeIndex === -1) {
        activeNodeIndex = this.query.regexMatchedNodes.findIndex((node) => {
          const range = selection.getRangeAt(0);

          if (range) {
            let sourceRange = document.createRange();
            sourceRange.setStart(node, 0);
            return range.compareBoundaryPoints(Range.START_TO_START, sourceRange) <= 0;
          } else {
            return false;
          }
        });
      }
    }
    this.query.activeRegexIndices = [Math.max(activeNodeIndex, 0), 0];
  }

  static getQueryFromRegexMatches() {
    // find()ing an empty query always returns false
    if (!this.query.regexMatches?.length) {
      return "";
    }
    let [row, col] = this.query.activeRegexIndices;
    return this.query.regexMatches[row][col];
  }

  static getNextQueryFromRegexMatches(backwards) {
    // find()ing an empty query always returns false
    if (!this.query.regexMatches?.length) {
      return "";
    }
    const stepSize = backwards ? -1 : 1;

    let [row, col] = this.query.activeRegexIndices;
    let numRows = this.query.regexMatches.length;
    col += stepSize;
    while (col < 0 || col >= this.query.regexMatches[row].length) {
      if (col < 0) {
        row += numRows - 1;
        row %= numRows;
        col += this.query.regexMatches[row].length;
      } else {
        col -= this.query.regexMatches[row].length;
        row += 1;
        row %= numRows;
      }
    }
    this.query.activeRegexIndices = [row, col];

    return this.query.regexMatches[row][col];
  }

  // Returns null if no search has been performed yet.
  static getQuery(backwards) {
    if (!this.query) return;
    // check if the query has been changed by a script in another frame
    const mostRecentQuery = FindModeHistory.getQuery();
    if (mostRecentQuery !== this.query.rawQuery) {
      this.updateQuery(mostRecentQuery);
    }

    return this.getNextQueryFromRegexMatches(backwards);
  }

  static saveQuery() {
    FindModeHistory.saveQuery(this.query.rawQuery);
  }

  // :options is an optional dict. valid parameters are 'caseSensitive' and 'backwards'.
  static execute(query, options) {
    let result = null;
    options = Object.assign({
      backwards: false,
      caseSensitive: !this.query.ignoreCase,
      colorSelection: true,
    }, options);
    if (query == null) {
      query = FindMode.getQuery(options.backwards);
    }

    if (options.colorSelection) {
      document.body.classList.add("vimiumFindMode");
      // ignore the selectionchange event generated by find()
      document.removeEventListener("selectionchange", this.restoreDefaultSelectionHighlight, true);
    }

    if (this.query.regexMatches?.length) {
      const [row, col] = this.query.activeRegexIndices;
      const node = this.query.regexMatchedNodes[row];
      const text = node.textContent;
      const matchIndices = getRegexMatchIndices(text, this.query.regexPattern);
      if (matchIndices.length > 0) {
        const startIndex = matchIndices[col];
        result = highlight(node, startIndex, query.length);
      }
    }

    // window.find focuses the |window| that it is called on. This gives us an opportunity to
    // (re-)focus another element/window, if that isn't the behaviour we want.
    if (options.postFindFocus != null) {
      options.postFindFocus.focus();
    }

    if (options.colorSelection) {
      setTimeout(
        () =>
          document.addEventListener("selectionchange", this.restoreDefaultSelectionHighlight, true),
        0,
      );
    }

    // We are either in normal mode ("n"), or find mode ("/"). We are not in insert mode.
    // Nevertheless, if a previous find landed in an editable element, then that element may still
    // be activated. In this case, we don't want to leave it behind (see #1412).
    if (document.activeElement && DomUtils.isEditable(document.activeElement)) {
      if (!DomUtils.isSelected(document.activeElement)) {
        document.activeElement.blur();
      }
    }

    return result;
  }

  // The user has found what they're looking for and is finished searching. We enter insert mode, if
  // possible.
  static handleEscape() {
    document.body.classList.remove("vimiumFindMode");
    // Removing the class does not re-color existing selections. we recreate the current selection
    // so it reverts back to the default color.
    const selection = window.getSelection();
    if (!selection.isCollapsed) {
      const range = window.getSelection().getRangeAt(0);
      window.getSelection().removeAllRanges();
      window.getSelection().addRange(range);
    }
    return focusFoundLink() || selectFoundInputElement();
  }

  // Save the query so the user can do further searches with it.
  static handleEnter() {
    focusFoundLink();
    document.body.classList.add("vimiumFindMode");
    return FindMode.saveQuery();
  }

  static findNext(backwards) {
    // Bail out if we don't have any query text.
    const nextQuery = FindMode.getQuery(backwards);
    if (!nextQuery) {
      HUD.show("No query to find.", 1000);
      return;
    }

    Marks.setPreviousPosition();
    FindMode.query.hasResults = FindMode.execute(nextQuery, { backwards });

    if (FindMode.query.hasResults) {
      focusFoundLink();
      return newPostFindMode();
    } else {
      return HUD.show(`No matches for '${FindMode.query.rawQuery}'`, 1000);
    }
  }

  checkReturnToViewPort() {
    if (this.options.returnToViewport) {
      window.scrollTo(this.scrollX, this.scrollY);
    }
  }
}

FindMode.restoreDefaultSelectionHighlight = forTrusted(() =>
  document.body.classList.remove("vimiumFindMode")
);

const getCurrentRange = function () {
  const selection = getSelection();
  if (DomUtils.getSelectionType(selection) === "None") {
    const range = document.createRange();
    range.setStart(document.body, 0);
    range.setEnd(document.body, 0);
    return range;
  } else {
    if (DomUtils.getSelectionType(selection) === "Range") {
      selection.collapseToStart();
    }
    return selection.getRangeAt(0);
  }
};

const getLinkFromSelection = function () {
  let node = window.getSelection().anchorNode;
  while (node && (node !== document.body)) {
    if (node.nodeName.toLowerCase() === "a") {
      return node;
    }
    node = node.parentNode;
  }
  return null;
};

const focusFoundLink = function () {
  if (FindMode.query.hasResults) {
    const link = getLinkFromSelection();
    if (link) {
      link.focus();
    }
  }
};

const selectFoundInputElement = function () {
  // Since the last focused element might not be the one currently pointed to by find (e.g. the
  // current one might be disabled and therefore unable to receive focus), we use the approximate
  // heuristic of checking that the last anchor node is an ancestor of our element.
  const findModeAnchorNode = document.getSelection().anchorNode;
  if (
    FindMode.query.hasResults && document.activeElement &&
    DomUtils.isSelectable(document.activeElement) &&
    DomUtils.isDOMDescendant(findModeAnchorNode, document.activeElement)
  ) {
    return DomUtils.simulateSelect(document.activeElement);
  }
};

// Retrieve the starting indices of all matches of the queried pattern within the given text.
const getRegexMatchIndices = (text, regex) => {
  const indices = [];
  let match;

  while ((match = regex.exec(text)) !== null) {
    if (!match[0]) {
      break;
    }
    indices.push(match.index);
  }

  return indices;
};

// Highlights text starting from the given startIndex with the specified length.
const highlight = (textNode, startIndex, length) => {
  if (startIndex === -1) {
    return false;
  }
  const selection = window.getSelection();
  const range = document.createRange();
  range.setStart(textNode, startIndex);
  range.setEnd(textNode, startIndex + length);
  selection.removeAllRanges();
  selection.addRange(range);

  // Ensure the highlighted element is visible within the viewport.
  const rect = range.getBoundingClientRect();
  if (rect.top < 0 || rect.bottom > window.innerHeight) {
    const screenHeight = window.innerHeight;
    window.scrollTo({
      top: window.scrollY + rect.top + rect.height / 2 - screenHeight / 2,
      behavior: "smooth",
    });
  }

  return true;
};

const getAllTextNodes = () => {
  const textNodes = [];

  function getAllTextNodes(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      textNodes.push(node);
    } else if (node.nodeType === Node.ELEMENT_NODE && node.checkVisibility()) {
      const children = node.childNodes;
      for (const child of children) {
        getAllTextNodes(child, textNodes);
      }
    }
  }

  getAllTextNodes(document.body);
  return textNodes;
};

window.PostFindMode = PostFindMode;
window.FindMode = FindMode;
