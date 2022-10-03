let findMode = null;

// Chrome creates a unique port for each MessageChannel, so there's a race condition between JavaScript
// messages of Vimium and browser messages during style recomputation. This duration was determined
// empirically. See https://github.com/philc/vimium/pull/3277#discussion_r283080348
const TIME_TO_WAIT_FOR_IPC_MESSAGES = 17;

// Set the input element's text, and move the cursor to the end.
const setTextInInputElement = function(inputElement, text) {
  inputElement.textContent = text;
  // Move the cursor to the end.  Based on one of the solutions here:
  // http://stackoverflow.com/questions/1125292/how-to-move-cursor-to-end-of-contenteditable-entity
  const range = document.createRange();
  range.selectNodeContents(inputElement);
  range.collapse(false);
  const selection = window.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
};

// Manually inject custom user styles.
document.addEventListener("DOMContentLoaded", () => DomUtils.injectUserCss());

const onKeyEvent = function(event) {
  // Handle <Enter> on "keypress", and other events on "keydown"; this avoids interence with CJK translation
  // (see #2915 and #2934).
  let rawQuery;
  if ((event.type === "keypress") && (event.key !== "Enter"))
    return null;
  if ((event.type === "keydown") && (event.key === "Enter"))
    return null;

  const inputElement = document.getElementById("hud-find-input");
  if (inputElement == null) // Don't do anything if we're not in find mode.
    return;

  if ((KeyboardUtils.isBackspace(event) && (inputElement.textContent.length === 0)) ||
     (event.key === "Enter") || KeyboardUtils.isEscape(event)) {

    inputElement.blur();
    UIComponentServer.postMessage({
      name: "hideFindMode",
      exitEventIsEnter: event.key === "Enter",
      exitEventIsEscape: KeyboardUtils.isEscape(event)
    });
  } else if (event.key === "ArrowUp") {
    if (rawQuery = FindModeHistory.getQuery(findMode.historyIndex + 1)) {
      findMode.historyIndex += 1;
      if (findMode.historyIndex === 0) {
        findMode.partialQuery = findMode.rawQuery;
      }
      setTextInInputElement(inputElement, rawQuery);
      findMode.executeQuery();
    }
  } else if (event.key === "ArrowDown") {
    findMode.historyIndex = Math.max(-1, findMode.historyIndex - 1);
    rawQuery = 0 <= findMode.historyIndex ? FindModeHistory.getQuery(findMode.historyIndex) : findMode.partialQuery;
    setTextInInputElement(inputElement, rawQuery);
    findMode.executeQuery();
  } else {
    return;
  }

  DomUtils.suppressEvent(event);
  return false;
};

document.addEventListener("keydown", onKeyEvent);
document.addEventListener("keypress", onKeyEvent);

const handlers = {
  show(data) {
    document.getElementById("hud").innerText = data.text;
    document.getElementById("hud").classList.add("vimiumUIComponentVisible");
    document.getElementById("hud").classList.remove("vimiumUIComponentHidden");
    document.getElementById("hud").classList.remove("hud-find");
  },
  hidden() {
    // We get a flicker when the HUD later becomes visible again (with new text) unless we reset its contents
    // here.
    document.getElementById("hud").innerText = "";
    document.getElementById("hud").classList.add("vimiumUIComponentHidden");
    document.getElementById("hud").classList.remove("vimiumUIComponentVisible");
  },

  showFindMode(data) {
    let executeQuery;
    const hud = document.getElementById("hud");
    hud.classList.add("hud-find");

    const inputElement = document.createElement("span");
    try { // NOTE(mrmr1993): Chrome supports non-standard "plaintext-only", which is what we *really* want.
      inputElement.contentEditable = "plaintext-only";
    } catch (error) { // Fallback to standard-compliant version.
      inputElement.contentEditable = "true";
    }
    inputElement.id = "hud-find-input";
    hud.appendChild(inputElement);

    inputElement.addEventListener("input", (executeQuery = function(event) {
      // On Chrome when IME is on, the order of events is:
      //   keydown, input.isComposing=true, keydown, input.true, ..., keydown, input.true, compositionend;
      // while on Firefox, the order is: keydown, input.true, ..., input.true, keydown, compositionend, input.false.
      // Therefore, check event.isComposing here, to avoid window focus changes during typing with IME,
      // since such changes will prevent normal typing on Firefox (see #3480)
      if (Utils.isFirefox() && event.isComposing)
        return;
      // Replace \u00A0 (&nbsp;) with a normal space.
      findMode.rawQuery = inputElement.textContent.replace("\u00A0", " ");
      UIComponentServer.postMessage({name: "search", query: findMode.rawQuery});
    }));

    const countElement = document.createElement("span");
    countElement.id = "hud-match-count";
    countElement.style.float = "right";
    hud.appendChild(countElement);
    Utils.setTimeout(TIME_TO_WAIT_FOR_IPC_MESSAGES, function() {
      // On Firefox, the page must first be focused before the HUD input element can be focused. #3460.
      if (Utils.isFirefox())
        window.focus();
      inputElement.focus();
    });

    findMode = {
      historyIndex: -1,
      partialQuery: "",
      rawQuery: "",
      executeQuery
    };
  },

  updateMatchesCount({matchCount, showMatchText}) {
    const countElement = document.getElementById("hud-match-count");
    if (countElement == null) // Don't do anything if we're not in find mode.
      return;

    if (Utils.isFirefox())
      document.getElementById("hud-find-input").focus()
    const countText = matchCount > 0 ?
      ` (${matchCount} Match${matchCount === 1 ? "" : "es"})` : " (No matches)";
    countElement.textContent = showMatchText ? countText : "";
  },

  copyToClipboard(data) {
    Utils.setTimeout(TIME_TO_WAIT_FOR_IPC_MESSAGES, function() {
      const focusedElement = document.activeElement;
      Clipboard.copy(data);
      if (focusedElement != null)
        focusedElement.focus();
      window.parent.focus();
      UIComponentServer.postMessage({name: "unfocusIfFocused"});
    });
  },

  pasteFromClipboard() {
    Utils.setTimeout(TIME_TO_WAIT_FOR_IPC_MESSAGES, function() {
      const focusedElement = document.activeElement;
      const data = Clipboard.paste();
      if (focusedElement != null)
        focusedElement.focus();
      window.parent.focus();
      UIComponentServer.postMessage({name: "pasteResponse", data});
    });
  },

  settings({ isFirefox }) {
     return Utils.isFirefox = () => isFirefox;
   }
};

UIComponentServer.registerHandler(function({data}) {
  const handler = handlers[data.name || data];
  if (handler)
    return handler(data);
});

FindModeHistory.init();
