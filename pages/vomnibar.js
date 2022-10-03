//
// This controls the contents of the Vomnibar iframe. We use an iframe to avoid changing the selection on the
// page (useful for bookmarklets), ensure that the Vomnibar style is unaffected by the page, and simplify key
// handling in vimium_frontend.js
//
const Vomnibar = {
  vomnibarUI: null, // the dialog instance for this window
  getUI() { return this.vomnibarUI; },
  completers: {},

  getCompleter(name) {
    if (!this.completers[name])
      this.completers[name] = new BackgroundCompleter(name);
    return this.completers[name];
  },

  activate(userOptions) {
    const options = {
      completer: "omni",
      query: "",
      newTab: false,
      selectFirst: false,
      keyword: null
    };
    Object.assign(options, userOptions);
    Object.assign(options, {refreshInterval: options.completer === "omni" ? 150 : 0});

    const completer = this.getCompleter(options.completer);
    if (this.vomnibarUI == null)
      this.vomnibarUI = new VomnibarUI();
    completer.refresh(this.vomnibarUI);
    this.vomnibarUI.setInitialSelectionValue(options.selectFirst ? 0 : -1);
    this.vomnibarUI.setCompleter(completer);
    this.vomnibarUI.setRefreshInterval(options.refreshInterval);
    this.vomnibarUI.setForceNewTab(options.newTab);
    this.vomnibarUI.setQuery(options.query);
    this.vomnibarUI.setKeyword(options.keyword);
    this.vomnibarUI.update(true);
  },

  hide() {
    if (this.vomnibarUI)
      this.vomnibarUI.hide();
  },

  onHidden() {
    if (this.vomnibarUI)
      this.vomnibarUI.onHidden()
  }
};

class VomnibarUI {
  constructor() {
    this.onKeyEvent = this.onKeyEvent.bind(this);
    this.onInput = this.onInput.bind(this);
    this.update = this.update.bind(this);
    this.refreshInterval = 0;
    this.onHiddenCallback = null;
    this.initDom();
  }

  setQuery(query) { this.input.value = query; }
  setKeyword(keyword) { this.customSearchMode = keyword; }
  setInitialSelectionValue(initialSelectionValue) {
    this.initialSelectionValue = initialSelectionValue;
  }
  setRefreshInterval(refreshInterval) {
    this.refreshInterval = refreshInterval;
  }
  setForceNewTab(forceNewTab) {
    this.forceNewTab = forceNewTab;
  }
  setCompleter(completer) {
    this.completer = completer;
    this.reset();
  }
  setKeywords(keywords) {
    this.keywords = keywords;
  }

  // The sequence of events when the vomnibar is hidden is as follows:
  // 1. Post a "hide" message to the host page.
  // 2. The host page hides the vomnibar.
  // 3. When that page receives the focus, and it posts back a "hidden" message.
  // 3. Only once the "hidden" message is received here is any required action  invoked (in onHidden).
  // This ensures that the vomnibar is actually hidden before any new tab is created, and avoids flicker after
  // opening a link in a new tab then returning to the original tab (see #1485).
  hide(onHiddenCallback = null) {
    this.onHiddenCallback = onHiddenCallback;
    this.input.blur();
    UIComponentServer.postMessage("hide");
    this.reset();
  }

  onHidden() {
    if (typeof this.onHiddenCallback === 'function') {
      this.onHiddenCallback();
    }
    this.onHiddenCallback = null;
    return this.reset();
  }

  reset() {
    this.clearUpdateTimer();
    this.completionList.style.display = "";
    this.input.value = "";
    this.completions = [];
    this.previousInputValue = null;
    this.customSearchMode = null;
    this.selection = this.initialSelectionValue;
    this.keywords = [];
    this.seenTabToOpenCompletionList = false;
    if (this.completer != null) {
      this.completer.reset();
    }
  }

  updateSelection() {
    // For custom search engines, we suppress the leading term (e.g. the "w" of "w query terms") within the
    // vomnibar input.
    if (this.lastResponse.isCustomSearch && (this.customSearchMode == null)) {
      const queryTerms = this.input.value.trim().split(/\s+/);
      this.customSearchMode = queryTerms[0];
      this.input.value = queryTerms.slice(1).join(" ");
    }

    // For suggestions for custom search engines, we copy the suggested text into the input when the item is
    // selected, and revert when it is not.  This allows the user to select a suggestion and then continue
    // typing.
    if ((0 <= this.selection) && (this.completions[this.selection].insertText != null)) {
      if (this.previousInputValue == null) { this.previousInputValue = this.input.value; }
      this.input.value = this.completions[this.selection].insertText;
    } else if (this.previousInputValue != null) {
      this.input.value = this.previousInputValue;
      this.previousInputValue = null;
    }

    // Highlight the selected entry, and only the selected entry.
    for (let i = 0, end = this.completionList.children.length; i < end; i++) {
      this.completionList.children[i].className = (i === this.selection ? "vomnibarSelected" : "");
    }
  }

  // Returns the user's action ("up", "down", "tab", etc, or null) based on their keypress.  We support the
  // arrow keys and various other shortcuts, and this function hides the event-decoding complexity.
  actionFromKeyEvent(event) {
    const key = KeyboardUtils.getKeyChar(event);
    // Handle <Enter> on "keypress", and other events on "keydown"; this avoids interence with CJK translation
    // (see #2915 and #2934).
    if ((event.type === "keypress") && (key !== "enter")) { return null; }
    if ((event.type === "keydown") && (key === "enter")) { return null; }
    if (KeyboardUtils.isEscape(event)) {
      return "dismiss";
    } else if ((key === "up") ||
        (event.shiftKey && (event.key === "Tab")) ||
        (event.ctrlKey && ((key === "k") || (key === "p")))) {
      return "up";
    } else if ((event.key === "Tab") && !event.shiftKey) {
      return "tab";
    } else if ((key === "down") ||
        (event.ctrlKey && ((key === "j") || (key === "n")))) {
      return "down";
    } else if (event.ctrlKey && (key === "enter")) {
      return "ctrl-enter";
    } else if (event.key === "Enter") {
      return "enter";
    } else if ((event.key === "Delete") && event.shiftKey && !event.ctrlKey && !event.altKey) {
      return "remove";
    } else if (KeyboardUtils.isBackspace(event)) {
      return "delete";
    }

    return null;
  }

  onKeyEvent(event) {
    let action, completion;
    this.lastAction = (action = this.actionFromKeyEvent(event));
    if (!action)
      return true; // pass through

    const openInNewTab = this.forceNewTab || event.shiftKey || event.ctrlKey || event.altKey || event.metaKey;
    if (action === "dismiss") {
      this.hide();
    } else if ([ "tab", "down" ].includes(action)) {
      if ((action === "tab") &&
          (this.completer.name === "omni") &&
          !this.seenTabToOpenCompletionList &&
          (this.input.value.trim().length === 0)) {
        this.seenTabToOpenCompletionList = true;
        this.update(true);
      } else if (this.completions.length > 0) {
        this.selection += 1;
        if (this.selection === this.completions.length)
          this.selection = this.initialSelectionValue;
        this.updateSelection();
      }
    } else if (action === "up") {
      this.selection -= 1;
      if (this.selection < this.initialSelectionValue)
        this.selection = this.completions.length - 1;
      this.updateSelection();
    } else if (action === "enter") {
      const c = this.completions[this.selection];
      const isCustomSearchPrimarySuggestion = c && c.isPrimarySuggestion &&
            this.lastResponse.engine && this.lastResponse.engine.searchUrl;
      if ((this.selection === -1) || isCustomSearchPrimarySuggestion) {
        let query = this.input.value.trim();
        // <Enter> on an empty query is a no-op.
        if (!(query.length > 0))
          return;
        // First case (@selection == -1).
        // If the user types something and hits enter without selecting a completion from the list, then:
        //   - If a search URL has been provided, then use it.  This is custom search engine request.
        //   - Otherwise, send the query to the background page, which will open it as a URL or create a
        //     default search, as appropriate.
        //
        // Second case (isCustomSearchPrimarySuggestion).
        // Alternatively, the selected completion could be the primary selection for a custom search engine.
        // Because the the suggestions are updated asynchronously in omni mode, the user may have typed more
        // text than that which is included in the URL associated with the primary suggestion.  Therefore, to
        // avoid a race condition, we construct the query from the actual contents of the input (query).
        if (isCustomSearchPrimarySuggestion)
          query = Utils.createSearchUrl(query, this.lastResponse.engine.searchUrl);
        this.hide(() => Vomnibar.getCompleter().launchUrl(query, openInNewTab));
      } else {
        completion = this.completions[this.selection];
        this.hide(() => completion.performAction(openInNewTab));
      }
    } else if (action === "ctrl-enter") {
      // Populate the vomnibar with the current selection's URL.
      if (!this.customSearchMode && (this.selection >= 0)) {
          if (this.previousInputValue == null) { this.previousInputValue = this.input.value; }
          this.input.value = this.completions[this.selection] != null ? this.completions[this.selection].url : undefined;
          this.input.scrollLeft = this.input.scrollWidth;
        }
    } else if (action === "delete") {
      if (this.customSearchMode && (this.input.selectionEnd === 0)) {
        // Normally, with custom search engines, the keyword (e,g, the "w" of "w query terms") is suppressed.
        // If the cursor is at the start of the input, then reinstate the keyword (the "w").
        this.input.value = this.customSearchMode + this.input.value.trimStart();
        this.input.selectionStart = (this.input.selectionEnd = this.customSearchMode.length);
        this.customSearchMode = null;
        this.update(true);
      } else if (this.seenTabToOpenCompletionList && (this.input.value.trim().length === 0)) {
        this.seenTabToOpenCompletionList = false;
        this.update(true);
      } else {
        return true; // Do not suppress event.
      }
    } else if ((action === "remove") && (0 <= this.selection)) {
      completion = this.completions[this.selection];
      console.log(completion);
    }

    // It seems like we have to manually suppress the event here and still return true.
    event.stopImmediatePropagation();
    event.preventDefault();
    return true;
  }

  // Return the background-page query corresponding to the current input state.  In other words, reinstate any
  // search engine keyword which is currently being suppressed, and strip any prompted text.
  getInputValueAsQuery() {
    return ((this.customSearchMode != null) ? this.customSearchMode + " " : "") + this.input.value;
  }

  updateCompletions(callback = null) {
    return this.completer.filter({
      query: this.getInputValueAsQuery(),
      seenTabToOpenCompletionList: this.seenTabToOpenCompletionList,
      callback: lastResponse => {
        this.lastResponse = lastResponse;
        const { results } = this.lastResponse;
        this.completions = results;
        this.selection = (this.completions[0] != null ? this.completions[0].autoSelect : undefined) ? 0 : this.initialSelectionValue;
        // Update completion list with the new suggestions.
        this.completionList.innerHTML = this.completions.map(completion => `<li>${completion.html}</li>`).join("");
        this.completionList.style.display = this.completions.length > 0 ? "block" : "";
        this.selection = Math.min(this.completions.length - 1, Math.max(this.initialSelectionValue, this.selection));
        this.updateSelection();
        if (callback)
          return callack();
      }
    });
  }

  onInput() {
    let updateSynchronously;
    this.seenTabToOpenCompletionList = false;
    this.completer.cancel();
    if ((0 <= this.selection) && this.completions[this.selection].customSearchMode && !this.customSearchMode) {
      this.customSearchMode = this.completions[this.selection].customSearchMode;
      updateSynchronously = true;
    }
    // If the user types, then don't reset any previous text, and reset the selection.
    if (this.previousInputValue != null) {
      this.previousInputValue = null;
      this.selection = -1;
    }
    return this.update(updateSynchronously);
  }

  clearUpdateTimer() {
    if (this.updateTimer != null) {
      window.clearTimeout(this.updateTimer);
      this.updateTimer = null;
    }
  }

  shouldActivateCustomSearchMode() {
    const queryTerms = this.input.value.trimStart().split(/\s+/);
    return (1 < queryTerms.length) && Array.from(this.keywords).includes(queryTerms[0]) && !this.customSearchMode;
  }

  update(updateSynchronously, callback = null) {
    // If the query text becomes a custom search (the user enters a search keyword), then we need to force a
    // synchronous update (so that the state is updated immediately).
    if (updateSynchronously == null) { updateSynchronously = false; }
    if (!updateSynchronously) { updateSynchronously = this.shouldActivateCustomSearchMode(); }
    if (updateSynchronously) {
      this.clearUpdateTimer();
      this.updateCompletions(callback);
    } else if ((this.updateTimer == null)) {
      // Update asynchronously for a better user experience, and to take some load off the CPU (not every
      // keystroke will cause a dedicated update).
      this.updateTimer = Utils.setTimeout(this.refreshInterval, () => {
        this.updateTimer = null;
        return this.updateCompletions(callback);
      });
    }

    this.input.focus();
  }

  initDom() {
    this.box = document.getElementById("vomnibar");

    this.input = this.box.querySelector("input");
    this.input.addEventListener("input", this.onInput);
    this.input.addEventListener("keydown", this.onKeyEvent);
    this.input.addEventListener("keypress", this.onKeyEvent);
    this.completionList = this.box.querySelector("ul");
    this.completionList.style.display = "";

    window.addEventListener("focus", () => this.input.focus());
    // A click in the vomnibar itself refocuses the input.
    this.box.addEventListener("click", event => {
      this.input.focus();
      return event.stopImmediatePropagation();
    });
    // A click anywhere else hides the vomnibar.
    document.addEventListener("click", () => this.hide());
  }
}

//
// Sends requests to a Vomnibox completer on the background page.
//
class BackgroundCompleter {
  // The "name" is the background-page completer to connect to: "omni", "tabs", or "bookmarks".
  constructor(name) {

    // These are the actions we can perform when the user selects a result.
    this.name = name;
    this.completionActions = {
      navigateToUrl(url) { return openInNewTab => Vomnibar.getCompleter().launchUrl(url, openInNewTab); },
      switchToTab(tabId) { return () => chrome.runtime.sendMessage({handler: "selectSpecificTab", id: tabId}); }
    };

    this.port = chrome.runtime.connect({name: "completions"});
    this.messageId = null;
    this.reset();

    this.port.onMessage.addListener(msg => {
      switch (msg.handler) {
      case "keywords":
        this.keywords = msg.keywords;
        return this.lastUI.setKeywords(this.keywords);
      case "completions":
        if (msg.id === this.messageId) {
          // The result objects coming from the background page will be of the form:
          //   { html: "", type: "", url: "", ... }
          // Type will be one of [tab, bookmark, history, domain, search], or a custom search engine description.
          for (let result of msg.results) {
            Object.assign(result, {
              performAction:
              result.type === "tab" ?
                this.completionActions.switchToTab(result.tabId) :
                this.completionActions.navigateToUrl(result.url)
            });
          }

          // Handle the message, but only if it hasn't arrived too late.
          return this.mostRecentCallback(msg);
        }
        break;
      }
    });
  }

  filter(request) {
    const { query, callback } = request;
    this.mostRecentCallback = callback;

    this.port.postMessage(Object.assign(request, {
      handler: "filter",
      name: this.name,
      id: (this.messageId = Utils.createUniqueId()),
      queryTerms: query.trim().split(/\s+/).filter(s => 0 < s.length),
      // We don't send these keys.
      callback: null
    }));
  }

  reset() {
    this.keywords = [];
  }

  refresh(lastUI) {
    this.lastUI = lastUI;
    this.reset();
    return this.port.postMessage({name: this.name, handler: "refresh"});
  }

  cancel() {
    // Inform the background completer that it may (should it choose to do so) abandon any pending query
    // (because the user is typing, and there will be another query along soon).
    this.port.postMessage({name: this.name, handler: "cancel"});
  }

  launchUrl(url, openInNewTab) {
    // If the URL is a bookmarklet (so, prefixed with "javascript:"), then we always open it in the current
    // tab.
    if (openInNewTab)
      openInNewTab = !Utils.hasJavascriptPrefix(url);
    chrome.runtime.sendMessage({
      handler: openInNewTab ? "openUrlInNewTab" : "openUrlInCurrentTab",
      url
    });
  }
}

UIComponentServer.registerHandler(function(event) {
  switch (event.data.name != null ? event.data.name : event.data) {
    case "hide": Vomnibar.hide(); break;
    case "hidden": Vomnibar.onHidden(); break;
    case "activate": Vomnibar.activate(event.data); break;
  }
});

document.addEventListener("DOMContentLoaded", function() {
  DomUtils.injectUserCss(); // Manually inject custom user styles.
});

window.Vomnibar = Vomnibar;
