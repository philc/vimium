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
      ? FindMode.getNextQueryFromRegexMatches(0)
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

    // If we are dealing with a regex, grep for all matches in the text, and then call window.find()
    // on them sequentially so the browser handles the scrolling / text selection.
    // If we are doing a basic plain string match, we still want to grep for matches of the string,
    // so we can show a the number of results.
    try {
      pattern = new RegExp(regexPattern, `g${this.query.ignoreCase ? "i" : ""}`);
    } catch {
      // If we catch a SyntaxError, assume the user is not done typing yet and return quietly.
      return;
    }

    let regexMatches;
    if (this.query.isRegex && regexPattern) {
      const matchedElements = Array.from(document.body.querySelectorAll("*")).filter((element) => {
        return element.checkVisibility() &&
          !element.childElementCount &&
          element.innerText &&
          element.innerText.match(pattern);
      });
      const matches = matchedElements.map((element) => element.innerText.match(pattern));
      regexMatches = matches.flat();
      this.query.regexMatches = regexMatches;
      this.query.regexPattern = pattern;
      this.query.regexMatchedElements = matchedElements;
      this.query.regexMatchesIn2DArray = matches;
      this.query.hasResults = regexMatches.length > 0;
    } else {
      // innerText will not return the text of hidden elements, and strip out tags while preserving
      // newlines.
      // NOTE(mrmr1993): innerText doesn't include the text contents of <input>s and <textarea>s. See
      // #1118.
      const text = document.body.innerText;
      regexMatches = text.match(pattern);
    }

    if (this.query.isRegex) {
      this.query.activeRegexIndex = 0;
    }

    return this.query.matchCount = regexMatches != null ? regexMatches.length : null;
  }

  static getNextQueryFromRegexMatches(stepSize) {
    // find()ing an empty query always returns false
    if (!this.query.regexMatches) {
      return "";
    }

    const totalMatches = this.query.regexMatches.length;
    this.query.activeRegexIndex += stepSize + totalMatches;
    this.query.activeRegexIndex %= totalMatches;

    return this.query.regexMatches[this.query.activeRegexIndex];
  }

  // Returns null if no search has been performed yet.
  static getQuery(backwards) {
    if (!this.query) return;
    // check if the query has been changed by a script in another frame
    const mostRecentQuery = FindModeHistory.getQuery();
    if (mostRecentQuery !== this.query.rawQuery) {
      this.updateQuery(mostRecentQuery);
    }

    if (this.query.isRegex) {
      return this.getNextQueryFromRegexMatches(backwards ? -1 : 1);
    } else {
      return this.query.parsedQuery;
    }
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

    try {
      if (FindMode.query.isRegex && this.query.hasResults) {
        const [elementIndex, matchIndex] = calculate2DArrayPosition(
          this.query.regexMatchesIn2DArray,
          this.query.activeRegexIndex,
        );
        const element = this.query.regexMatchedElements[elementIndex];
        const textContent = element.innerText;
        const matchindices = getRegexMatchindices(textContent, this.query.regexPattern);
        if (matchindices.length > 0) {
          const startIndex = matchindices[matchIndex];
          result = highlight(element, startIndex, query.length);
        }
      } else {
        result = window.find(
          query,
          options.caseSensitive,
          options.backwards,
          true,
          false,
          false,
          false,
        );
      }
    } catch { /* swallow */ } // Failed searches throw on Firefox.

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

// Calculate the original row and column indices in a 2D array based on a flattened index.
const calculate2DArrayPosition = (a2DArray, offset) => {
  let row = 0;
  let col = offset;

  for (let i = 0; i < a2DArray.length; i++) {
    const currentRow = a2DArray[i];

    if (col < currentRow.length) {
      break;
    } else {
      row++;
      col -= currentRow.length;
    }
  }

  return [row, col];
};

// Retrieve the starting indices of all matches of the queried pattern within the given text.
const getRegexMatchindices = (text, regex) => {
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
const highlight = (element, startIndex, length) => {
  if (startIndex === -1) {
    return false;
  }
  const selection = window.getSelection();
  const range = document.createRange();
  range.setStart(element.firstChild, startIndex);
  range.setEnd(element.firstChild, startIndex + length);
  selection.removeAllRanges();
  selection.addRange(range);

  // Ensure the highlighted element is visible within the viewport.
  const rect = element.getBoundingClientRect();
  if (rect.top < 0 || rect.bottom > window.innerHeight) {
    element.scrollIntoView({ block: "center" });
  }

  return true;
};

window.PostFindMode = PostFindMode;
window.FindMode = FindMode;
