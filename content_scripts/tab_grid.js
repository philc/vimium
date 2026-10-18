//
// The tab grid: an overlay showing the current window's tabs (up to MAX_TABS) with thumbnails,
// opened via the "showTabGrid" command (Shift+D by default).
//
// Selection follows Vimium's link-hint design: each card carries a hint marker generated from the
// user's linkHintCharacters setting (displayed uppercase, like link hints), typing a hint opens
// that tab, Backspace pops a typed character, and typing a character no hint starts with dismisses
// the grid. Arrow keys / Tab move the highlight (Enter opens it), x or Delete closes the
// highlighted tab, and each card has its own close button.
//

const TabGrid = {
  MAX_TABS: 9,
  // The tab descriptors currently shown, set by show().
  tabs: [],
  // One hint string per tab, generated from the linkHintCharacters setting.
  hintStrings: [],
  // Characters typed so far for multi-character hints.
  hintKeystrokeQueue: [],
  selectedIndex: 0,
  activeTabThumbnail: null,
  mode: null,
  overlayElement: null,

  isShowing() {
    return this.overlayElement != null;
  },

  async toggle() {
    if (this.isShowing()) {
      this.hide();
    } else {
      await this.show();
    }
  },

  async show() {
    this.hide();
    const data = await chrome.runtime.sendMessage({ handler: "getTabGridData" });
    const tabs = (data?.tabs || []).slice(0, this.MAX_TABS);
    if (tabs.length == 0) {
      globalThis.HUD?.show?.("No tabs to show.", 1500);
      return;
    }
    this.tabs = tabs;
    this.hintStrings = this.getHintStrings(tabs.length);
    this.hintKeystrokeQueue = [];
    this.activeTabThumbnail = data.activeTabThumbnail || null;
    this.selectedIndex = Math.max(
      0,
      tabs.findIndex((tab) => tab.active),
    );
    this.overlayElement = this.buildGridElement(tabs, this.activeTabThumbnail, this.hintStrings);
    document.documentElement.appendChild(this.overlayElement);
    this.updateSelection();
    this.mode = new Mode();
    this.mode.init({
      name: "tab-grid",
      indicator: "Tab grid",
      exitOnEscape: true,
      singleton: "tab-grid",
      keydown: (event) => this.onKeyDown(event),
    });
    this.mode.onExit(() => this.hide());
  },

  hide() {
    if (this.overlayElement) {
      this.overlayElement.remove();
      this.overlayElement = null;
    }
    this.tabs = [];
    this.hintStrings = [];
    this.hintKeystrokeQueue = [];
    this.selectedIndex = 0;
    this.activeTabThumbnail = null;
    if (this.mode) {
      const mode = this.mode;
      this.mode = null;
      mode.exit();
    }
  },

  selectTab(tabId) {
    this.hide();
    chrome.runtime.sendMessage({ handler: "selectSpecificTab", id: tabId });
  },

  // Closes one tab from the grid. The grid stays open; only the tab's card is removed.
  // Closing the current tab dismisses the grid, since the grid's own page is going away.
  async closeTab(tabId) {
    const index = this.tabs.findIndex((tab) => tab.id == tabId);
    if ((index < 0) || this.tabs[index].active) {
      this.hide();
      await chrome.runtime.sendMessage({ handler: "removeTabById", id: tabId }).catch(() => {});
      return;
    }
    // The tab is gone whether the close succeeds or was already closed, so drop its card either
    // way.
    await chrome.runtime.sendMessage({ handler: "removeTabById", id: tabId }).catch(() => {});
    if (!this.isShowing()) return;
    this.tabs.splice(index, 1);
    this.hintStrings.splice(index, 1);
    const cards = this.overlayElement.querySelectorAll(".vimium-tab-grid-card");
    cards[index]?.remove();
    if (this.tabs.length == 0) {
      this.hide();
      return;
    }
    const grid = this.overlayElement.querySelector(".vimium-tab-grid-grid");
    if (grid) grid.style.gridTemplateColumns = `repeat(${this.gridColumns()}, 1fr)`;
    this.selectedIndex = Math.min(this.selectedIndex, this.tabs.length - 1);
    this.updateSelection();
    this.updateMarkers();
  },

  gridColumns() {
    return Math.max(1, Math.min(3, this.tabs.length));
  },

  // The index reached by moving one step in direction from current. Pure, for tests.
  nextIndex(current, direction, count, columns) {
    if (count <= 0) return 0;
    switch (direction) {
      case "left":
        return Math.max(0, current - 1);
      case "right":
        return Math.min(count - 1, current + 1);
      case "up":
        return Math.max(0, current - columns);
      case "down":
        return Math.min(count - 1, current + columns);
      default:
        return current;
    }
  },

  // Hint strings identifying count tabs, from the user's linkHintCharacters setting. Falls back
  // to the default characters when the setting is unusable (AlphabetHints requires 2+ chars).
  getHintStrings(count) {
    let chars = Settings.get("linkHintCharacters");
    if (!chars || chars.length <= 1) {
      chars = Settings.defaultOptions.linkHintCharacters;
    }
    return this.buildHintStrings(count, chars.toLowerCase());
  },

  // The same shortest-unique-strings algorithm as AlphabetHints.hintStrings in link_hints.js.
  buildHintStrings(count, linkHintCharacters) {
    let hints = [""];
    let offset = 0;
    while (((hints.length - offset) < count) || (hints.length === 1)) {
      const hint = hints[offset++];
      for (const ch of linkHintCharacters) {
        hints.push(ch + hint);
      }
    }
    hints = hints.slice(offset, offset + count);
    return hints.sort().map((str) => [...str].reverse().join(""));
  },

  // Tabs whose hints start with the queued keystrokes.
  getMatchingTabs() {
    const matchString = this.hintKeystrokeQueue.join("");
    return this.tabs.filter((_tab, index) => this.hintStrings[index].startsWith(matchString));
  },

  onKeyDown(event) {
    if (event.repeat) return handlerStack.suppressEvent;
    const key = event.key;
    if (key == "Delete") {
      const tab = this.tabs[this.selectedIndex];
      if (tab) this.closeTab(tab.id);
      return handlerStack.suppressEvent;
    }
    if (KeyboardUtils.isBackspace(event)) {
      if (this.hintKeystrokeQueue.length > 0) {
        this.hintKeystrokeQueue.pop();
        this.updateMarkers();
      } else {
        this.hide();
      }
      return handlerStack.suppressEvent;
    }
    if ((key == "Enter") || (key == " ")) {
      const tab = this.tabs[this.selectedIndex];
      if (tab) this.selectTab(tab.id);
      return handlerStack.suppressEvent;
    }
    let direction = null;
    switch (key) {
      case "ArrowLeft":
        direction = "left";
        break;
      case "ArrowRight":
        direction = "right";
        break;
      case "ArrowUp":
        direction = "up";
        break;
      case "ArrowDown":
        direction = "down";
        break;
      case "Tab":
        direction = event.shiftKey ? "left" : "right";
        break;
    }
    if (direction) {
      this.selectedIndex = this.nextIndex(
        this.selectedIndex,
        direction,
        this.tabs.length,
        this.gridColumns(),
      );
      this.updateSelection();
      return handlerStack.suppressEvent;
    }
    // Hint matching, like AlphabetHints: lowercase single characters extend the queue.
    const keyChar = KeyboardUtils.getKeyChar(event).toLowerCase();
    if (keyChar.length == 1) {
      const matchString = this.hintKeystrokeQueue.join("") + keyChar;
      const matched = this.tabs.filter((_tab, index) =>
        this.hintStrings[index].startsWith(matchString)
      );
      if (matched.length > 0) {
        this.hintKeystrokeQueue.push(keyChar);
        if (matched.length == 1) {
          this.selectTab(matched[0].id);
        } else {
          this.updateMarkers();
        }
        return handlerStack.suppressEvent;
      }
      // No hint starts with this; x closes the highlighted tab (unless hints are being typed).
      if ((this.hintKeystrokeQueue.length == 0) && (keyChar == "x")) {
        const tab = this.tabs[this.selectedIndex];
        if (tab) this.closeTab(tab.id);
        return handlerStack.suppressEvent;
      }
      // Like link hints, a character matching nothing dismisses the grid.
      this.hide();
    }
    // The grid is modal: swallow any other keys while it is open.
    return handlerStack.suppressEvent;
  },

  updateSelection() {
    if (!this.overlayElement) return;
    const cards = this.overlayElement.querySelectorAll(".vimium-tab-grid-card");
    cards.forEach((card, index) => {
      card.classList.toggle("vimium-tab-grid-selected", index == this.selectedIndex);
    });
  },

  // Shows only the cards matching the queued keystrokes, highlighting the typed hint prefix like
  // link hints do, and updates the mode indicator with the typed characters.
  updateMarkers() {
    const typedLength = this.hintKeystrokeQueue.length;
    if (this.overlayElement) {
      const cards = this.overlayElement.querySelectorAll(".vimium-tab-grid-card");
      cards.forEach((card, index) => {
        const isMatch = this.hintStrings[index].startsWith(this.hintKeystrokeQueue.join(""));
        card.style.display = isMatch ? "" : "none";
        const spans = card.querySelectorAll(".vimium-tab-grid-hint span");
        spans.forEach((span, spanIndex) => {
          span.classList.toggle("matchingCharacter", spanIndex < typedLength);
        });
      });
    }
    const typed = this.hintKeystrokeQueue.join("");
    this.mode?.setIndicator(typed ? `Tab grid: "${typed}".` : "Tab grid");
  },

  // Only http(s) and image data URLs may be used as thumbnails, so a compromised tab cannot
  // inject e.g. a javascript: URL into the grid.
  isSafeThumbnailUrl(url) {
    return (typeof url == "string") && /^(https?:\/\/|data:image\/)/.test(url);
  },

  // One span per character (like link_hints.js's spanWrap), so typed characters can be
  // highlighted. Hint strings contain only the user's hint characters, so this is safe to render
  // as HTML.
  spanWrapHint(hintString) {
    return [...hintString].map((char) => `<span class="vimium-reset">${char}</span>`).join("");
  },

  buildGridElement(tabs, activeTabThumbnail, hintStrings) {
    const visible = tabs.slice(0, this.MAX_TABS);
    const overlay = DomUtils.createElement("div");
    overlay.id = "vimium-tab-grid-overlay";
    overlay.className = "vimium-reset";

    const backdrop = DomUtils.createElement("div");
    backdrop.className = "vimium-tab-grid-backdrop";
    backdrop.addEventListener("click", () => this.hide());
    overlay.appendChild(backdrop);

    const dialog = DomUtils.createElement("div");
    dialog.className = "vimium-tab-grid-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-label", "Open tabs");

    const header = DomUtils.createElement("div");
    header.className = "vimium-tab-grid-header";
    const hint = DomUtils.createElement("span");
    hint.textContent = "Open tabs — type a hint to select, x closes highlighted, Esc closes";
    header.appendChild(hint);
    const closeButton = DomUtils.createElement("button");
    closeButton.type = "button";
    closeButton.className = "vimium-tab-grid-close";
    closeButton.setAttribute("aria-label", "Close");
    closeButton.textContent = "×";
    closeButton.addEventListener("click", () => this.hide());
    header.appendChild(closeButton);
    dialog.appendChild(header);

    const grid = DomUtils.createElement("div");
    grid.className = "vimium-tab-grid-grid";
    grid.style.gridTemplateColumns = `repeat(${Math.max(1, Math.min(3, visible.length))}, 1fr)`;
    visible.forEach((tab, index) => {
      grid.appendChild(this.buildCard(tab, activeTabThumbnail, hintStrings[index]));
    });
    dialog.appendChild(grid);

    overlay.appendChild(dialog);
    return overlay;
  },

  buildCard(tab, activeTabThumbnail, hintString) {
    const card = DomUtils.createElement("div");
    card.className = "vimium-tab-grid-card" + (tab.active ? " vimium-tab-grid-active" : "");
    card.setAttribute("role", "button");
    card.setAttribute("aria-label", `${hintString}: ${tab.title || tab.url || "Untitled tab"}`);
    card.addEventListener("click", () => this.selectTab(tab.id));

    const thumb = DomUtils.createElement("div");
    thumb.className = "vimium-tab-grid-thumb";
    const screenshot = tab.active ? activeTabThumbnail : null;
    const imgSrc = this.isSafeThumbnailUrl(screenshot)
      ? screenshot
      : (this.isSafeThumbnailUrl(tab.favIconUrl) ? tab.favIconUrl : null);
    if (imgSrc) {
      const img = DomUtils.createElement("img");
      img.setAttribute("src", imgSrc);
      img.setAttribute("alt", "");
      img.setAttribute("draggable", "false");
      img.className = imgSrc == screenshot
        ? "vimium-tab-grid-screenshot"
        : "vimium-tab-grid-favicon";
      thumb.appendChild(img);
    } else {
      const placeholder = DomUtils.createElement("div");
      placeholder.className = "vimium-tab-grid-placeholder";
      const letter = (tab.title || tab.url || "?").trim()[0] || "?";
      placeholder.textContent = letter.toUpperCase();
      thumb.appendChild(placeholder);
    }
    // The hint badge uses link hints' marker classes (and uppercase display), so it looks like a
    // link hint and honors the user's custom hint CSS.
    const badge = DomUtils.createElement("div");
    badge.className =
      "vimium-reset internal-vimium-hint-marker vimiumHintMarker vimium-tab-grid-hint";
    badge.innerHTML = this.spanWrapHint(hintString.toUpperCase());
    thumb.appendChild(badge);
    const closeTabButton = DomUtils.createElement("button");
    closeTabButton.type = "button";
    closeTabButton.className = "vimium-tab-grid-close-tab";
    closeTabButton.setAttribute("aria-label", `Close ${tab.title || tab.url || "tab"}`);
    closeTabButton.textContent = "×";
    closeTabButton.addEventListener("click", (event) => {
      event.stopPropagation();
      this.closeTab(tab.id);
    });
    thumb.appendChild(closeTabButton);
    card.appendChild(thumb);

    const meta = DomUtils.createElement("div");
    meta.className = "vimium-tab-grid-meta";
    const title = DomUtils.createElement("div");
    title.className = "vimium-tab-grid-title";
    title.textContent = tab.title || tab.url || "Untitled tab";
    meta.appendChild(title);
    const url = DomUtils.createElement("div");
    url.className = "vimium-tab-grid-url";
    url.textContent = tab.url || "";
    meta.appendChild(url);
    card.appendChild(meta);

    return card;
  },
};

globalThis.TabGrid = TabGrid;
