// NOTE(smblott). Ultimately, all of the FindMode-related code should be moved here.

// This prevents unmapped printable characters from being passed through to underlying page; see
// #1415. Only used by PostFindMode, below.
class SuppressPrintable extends Mode {
  constructor(options) {
    super();
    super.init(options);
    const handler = (event) =>
      KeyboardUtils.isPrintable(event) ? this.suppressEvent : this.continueBubbling;
    const initialType = globalThis.getSelection().type;

    // We use unshift here, so we see events after normal mode, so we only see unmapped keys.
    this.unshift({
      _name: `mode-${this.id}/suppress-printable`,
      keydown: handler,
      keypress: handler,
      keyup: () => {
        // If the selection type has changed (usually, no longer "Range"), then the user is
        // interacting with the input element, so we get out of the way. See discussion of option 5c
        // from #1415.
        if (globalThis.getSelection().type !== initialType) {
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

    // TODO(philc): I don't think this.query is ever used/accessed, because it's only accessed from
    // static methods. Consider splitting the static portions of this class into a separate class
    // called FindModeSingleton. Blending the two together is confusing.
    this.query = {
      rawQuery: "",
      parsedQuery: "",
      matchCount: 0,
      hasResults: false,
    };

    // Save the selection, so findInPlace can restore it.
    this.initialRange = getCurrentRange();
    // `backwards` is the search's direction, which n and N are relative to, as in Vim.
    FindMode.query = { rawQuery: "", backwards: Boolean(options.reverse) };

    if (options.returnToViewport) {
      this.scrollX = globalThis.scrollX;
      this.scrollY = globalThis.scrollY;
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
    // updateQuery builds the pattern and the list of matches, and makes the first match after the
    // current selection the active one. A backward search replaces that with the last match before
    // where the search started.
    FindMode.updateQuery(query);
    if (FindMode.query.backwards) {
      FindMode.selectLastMatchBefore(this.initialRange);
    }
    // Restore the selection. That way, we're always searching from the same place, so we
    // find the right match as the user adds matching characters, or removes previously-matched
    // characters. See #1434.
    this.restoreSelection();
    FindMode.query.hasResults = FindMode.execute(FindMode.getActiveMatchText(), options);
  }

  static updateQuery(query) {
    let pattern;
    if (!this.query) {
      this.query = {};
    }
    this.query.rawQuery = query;
    // the query can be treated differently (e.g. as a plain string versus regex) depending on the
    // presence of escape sequences. '\' is the escape character and needs to be escaped itself to
    // be used as a normal character. here we grep for the relevant escape sequences.
    this.query.isRegex = Settings.get("regexFindMode");
    // As in Vim, \c ignores case and \C matches it, overriding smartcase.
    let ignoreCase;
    this.query.parsedQuery = this.query.rawQuery.replace(
      /(\\{1,2})([rRcC]?)/g,
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
          case "c":
            ignoreCase = true;
            break;
          case "C":
            ignoreCase = false;
            break;
        }
        return "";
      },
    );

    // Implement smartcase.
    this.query.ignoreCase = ignoreCase ?? !Utils.hasUpperCase(this.query.parsedQuery);

    const regexPattern = this.query.isRegex
      ? this.query.parsedQuery
      : Utils.escapeRegexSpecialCharacters(this.query.parsedQuery);

    // Find every match up front, so we can show the number of results.
    try {
      pattern = new RegExp(regexPattern, `g${this.query.ignoreCase ? "i" : ""}`);
    } catch {
      // If we catch a SyntaxError, assume the user is not done typing yet and return quietly.
      return;
    }

    this.query.matches = findMatches(pattern);
    this.selectMatchAtSelection();
    return this.query.matchCount = this.query.matches.length;
  }

  // Makes the first match which starts at or after the selection the active one, wrapping around to
  // the page's first match if there is none.
  static selectMatchAtSelection() {
    const selection = globalThis.getSelection();
    const range = selection.rangeCount > 0 ? selection.getRangeAt(0) : null;
    const index = range ? countMatchesBefore(this.query.matches, range) : 0;
    this.query.activeMatchIndex = index < this.query.matches.length ? index : 0;
  }

  // Makes the last match which starts before `range` the active one, wrapping around to the page's
  // last match if there is none.
  static selectLastMatchBefore(range) {
    const matches = this.query.matches;
    if (!matches?.length) {
      return;
    }
    const index = countMatchesBefore(matches, range) - 1;
    this.query.activeMatchIndex = index >= 0 ? index : matches.length - 1;
  }

  // Returns "" if there are no matches.
  static getActiveMatchText() {
    return this.query.matches?.[this.query.activeMatchIndex]?.text ?? "";
  }

  // Moves to the next match, or the previous one if `backwards`, and returns its text. Returns ""
  // if there are no matches, which findNext reports as having no query.
  static selectNextMatch(backwards) {
    const count = this.query.matches?.length;
    if (!count) {
      return "";
    }
    const step = backwards ? -1 : 1;
    this.query.activeMatchIndex = (this.query.activeMatchIndex + step + count) % count;
    return this.getActiveMatchText();
  }

  // Returns null if no search has been performed yet.
  static getQuery(backwards) {
    if (!this.query) {
      return;
    }
    // check if the query has been changed by a script in another frame
    const mostRecentQuery = FindModeHistory.getQuery();
    if (mostRecentQuery !== this.query.rawQuery) {
      this.updateQuery(mostRecentQuery);
    }

    return this.selectNextMatch(backwards);
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
      document.body.classList.add("vimium-find-mode");
      // ignore the selectionchange event generated by find()
      document.removeEventListener("selectionchange", this.restoreDefaultSelectionHighlight, true);
    }

    const match = this.query.matches?.[this.query.activeMatchIndex];
    if (match) {
      result = highlight(match);
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
    document.body.classList.remove("vimium-find-mode");
    // Removing the class does not re-color existing selections. we recreate the current selection
    // so it reverts back to the default color.
    const selection = globalThis.getSelection();
    if (!selection.isCollapsed) {
      const range = globalThis.getSelection().getRangeAt(0);
      globalThis.getSelection().removeAllRanges();
      globalThis.getSelection().addRange(range);
    }
    return focusFoundLink() || selectFoundInputElement();
  }

  // Save the query so the user can do further searches with it.
  static handleEnter() {
    focusFoundLink();
    document.body.classList.add("vimium-find-mode");
    return FindMode.saveQuery();
  }

  // Repeats the search in its own direction, or in the opposite one if `reverse` is set.
  static findNext(reverse) {
    const backwards = Boolean(FindMode.query?.backwards) != reverse;
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
      globalThis.scrollTo(this.scrollX, this.scrollY);
    }
  }
}

FindMode.restoreDefaultSelectionHighlight = forTrusted(() =>
  document.body.classList.remove("vimium-find-mode")
);

const getCurrentRange = function () {
  const selection = getSelection();
  if (selection.type === "None") {
    const range = document.createRange();
    range.setStart(document.body, 0);
    range.setEnd(document.body, 0);
    return range;
  }

  if (selection.type === "Range") {
    selection.collapseToStart();
  }

  return selection.getRangeAt(0);
};

const getLinkFromSelection = function () {
  let node = globalThis.getSelection().anchorNode;
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

// Selects and reveals a match from findMatches. Returns false if the page has changed so that the
// match's offsets are no longer in its nodes.
const highlight = (match) => {
  const range = document.createRange();
  try {
    range.setStart(match.startNode, match.startOffset);
    range.setEnd(match.endNode, match.endOffset);
  } catch {
    return false;
  }
  const selection = globalThis.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);

  revealMatch(range, match.startNode.parentElement);
  return true;
};

// Returns how many of `matches`, which are in document order, start before `range` starts. This is
// a binary search, so it compares only a few matches with `range`.
const countMatchesBefore = (matches, range) => {
  let low = 0;
  let high = matches.length;
  while (low < high) {
    const mid = (low + high) >> 1;
    if (range.comparePoint(matches[mid].startNode, matches[mid].startOffset) < 0) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
};

// Returns every match of `pattern`, a global RegExp, in the page's displayed text, in document
// order. Each match is { text, startNode, startOffset, endNode, endOffset }. A match can span
// several text nodes, such as a phrase split across syntax-highlighting spans (#4623), but not a
// block boundary. This is how Chrome and Firefox's own find works.
const findMatches = (pattern) => {
  const matches = [];
  for (const run of getTextRuns()) {
    for (const match of run.text.matchAll(pattern)) {
      if (!match[0]) {
        continue;
      }
      const start = match.index;
      const end = start + match[0].length;
      const startPiece = findPiece(run.pieces, start, false);
      const endPiece = findPiece(run.pieces, end, true);
      matches.push({
        text: match[0],
        startNode: startPiece.node,
        startOffset: nodeOffset(startPiece, start, false),
        endNode: endPiece.node,
        endOffset: nodeOffset(endPiece, end, true),
      });
    }
  }
  return matches;
};

// Returns the piece of a text run which holds the character at `offset`, or, if `isEnd`, the
// character just before it. This is a binary search over the pieces' start offsets.
const findPiece = (pieces, offset, isEnd) => {
  let low = 0;
  let high = pieces.length - 1;
  while (low < high) {
    const mid = (low + high + 1) >> 1;
    const start = pieces[mid].start;
    if (isEnd ? start < offset : start <= offset) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return pieces[low];
};

// Maps an offset in a text run to an offset in the text node of `piece`, which holds it.
const nodeOffset = (piece, runOffset, isEnd) => {
  const offset = runOffset - piece.start;
  if (!piece.offsets) {
    return offset;
  }
  return isEnd ? piece.offsets[offset - 1] + 1 : piece.offsets[offset];
};

// How a text node's white-space style treats its whitespace.
const collapseAll = 0;
const preserveBreaks = 1;
const preserveAll = 2;

const whitespaceModes = {
  // Values of white-space-collapse.
  "collapse": collapseAll,
  "preserve-breaks": preserveBreaks,
  // Values of white-space, for Firefox before 124, which lacks white-space-collapse.
  "normal": collapseAll,
  "nowrap": collapseAll,
  "pre-line": preserveBreaks,
};

const getWhitespaceMode = (style) =>
  whitespaceModes[style.whiteSpaceCollapse ?? style.whiteSpace] ?? preserveAll;

// Collapses each run of whitespace in `text` to one space, as the page renders it. Returns the
// collapsed text, and the offset in `text` of each of its characters.
const collapseWhitespace = (text, mode, afterSpace) => {
  let collapsed = "";
  const offsets = [];
  for (let i = 0; i < text.length; i++) {
    let char = text[i];
    const isSpace = char === " " || char === "\t" || char === "\n" || char === "\r" ||
      char === "\f";
    if (isSpace && !(mode === preserveBreaks && char === "\n")) {
      if (afterSpace) {
        continue;
      }
      char = " ";
    }
    afterSpace = isSpace;
    collapsed += char;
    offsets.push(i);
  }
  return { collapsed, offsets };
};

// Splits the page's displayed text into runs, which find matches within. As in Chrome, a run ends
// at a block boundary, at an inline-block, and at a <br>. Each run is { text, pieces }, where each
// piece is { node, start, offsets }: the text node a part of the run came from, where that part
// starts in the run, and, if whitespace was collapsed, the node offset of each of its characters.
//
// This uses a TreeWalker rather than recursing through childNodes, because in Firefox, each DOM
// access from a content script is expensive. Recursing made each keystroke slow on large pages.
// See #4546.
const getTextRuns = () => {
  // For each element: whether it's displayed, the block its text belongs to, and how it treats
  // whitespace.
  const elementInfo = new Map();
  const getInfo = (element) => {
    let info = elementInfo.get(element);
    if (info === undefined) {
      const style = getComputedStyle(element);
      const parent = element.parentElement;
      const parentInfo = parent ? getInfo(parent) : null;
      const isContents = style.display === "contents";
      info = {
        // An element with display: contents has no box, so checkVisibility() is false for it, but
        // its children are shown if its parent is. Sites can set display: contents in a
        // stylesheet, so check the computed value. See #4561.
        displayed: element.checkVisibility() || (isContents && (parentInfo?.displayed ?? true)),
        block: (style.display === "inline" || isContents) && parentInfo
          ? parentInfo.block
          : element,
        whitespace: getWhitespaceMode(style),
      };
      elementInfo.set(element, info);
    }
    return info;
  };

  const runs = [];
  let run = null;
  let block = null;
  // Whether the run so far ends in collapsible whitespace, so that leading whitespace in the next
  // text node collapses into it.
  let afterSpace;
  const walker = document.createTreeWalker(
    document.body,
    NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT,
  );
  let node;
  while ((node = walker.nextNode())) {
    if (node.nodeType !== Node.TEXT_NODE) {
      if (node.nodeName === "BR") {
        block = null;
      }
      continue;
    }
    const info = getInfo(node.parentElement);
    if (!info.displayed) {
      continue;
    }
    if (info.block !== block) {
      block = info.block;
      run = { parts: [], pieces: [], length: 0 };
      runs.push(run);
      afterSpace = true;
    }

    let text = node.data;
    let offsets = null;
    if (info.whitespace === preserveAll) {
      afterSpace = false;
    } else {
      if (/[\t\n\r\f]| {2}/.test(text) || (afterSpace && text[0] === " ")) {
        ({ collapsed: text, offsets } = collapseWhitespace(text, info.whitespace, afterSpace));
      }
      if (text.length === 0) {
        continue;
      }
      afterSpace = text.endsWith(" ") || text.endsWith("\n");
    }
    // Chrome matches a typed space against a non-breaking one.
    text = text.replaceAll(" ", " ");
    run.pieces.push({ node, start: run.length, offsets });
    run.parts.push(text);
    run.length += text.length;
  }
  for (const run of runs) {
    run.text = run.parts.join("");
  }
  return runs;
};

const revealMatch = (range, element) => {
  // Scroll each enclosing pane until the match itself is visible within that pane.
  // Check the window viewport last, since scrolling a pane moves the match.
  for (let pane = element; pane && pane !== document.documentElement; pane = pane.parentElement) {
    if (pane === document.scrollingElement || pane.scrollHeight <= pane.clientHeight) {
      continue;
    }
    const canScrollVertically = /^(auto|scroll|hidden|overlay)$/.test(
      getComputedStyle(pane).overflowY,
    );
    if (!canScrollVertically) {
      continue;
    }
    const rect = range.getBoundingClientRect();
    const paneTop = pane.getBoundingClientRect().top + pane.clientTop;
    const paneBottom = paneTop + pane.clientHeight;
    if (rect.top < paneTop || rect.bottom > paneBottom) {
      const matchCenter = rect.top + rect.height / 2;
      const paneCenter = paneTop + pane.clientHeight / 2;
      pane.scrollBy({ top: matchCenter - paneCenter, behavior: "instant" });
    }
  }

  const rect = range.getBoundingClientRect();
  if (rect.top < 0 || rect.bottom > globalThis.innerHeight) {
    const screenHeight = globalThis.innerHeight;
    globalThis.scrollTo({
      top: globalThis.scrollY + rect.top + rect.height / 2 - screenHeight / 2,
      // Scroll instantly when we find a search result. This matches the behavior of Chrome and
      // Firefox's native search UI. See #4661.
      behavior: "instant",
    });
  }
};

globalThis.PostFindMode = PostFindMode;
globalThis.FindMode = FindMode;
