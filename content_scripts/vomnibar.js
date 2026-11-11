//
// This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
//
const Vomnibar = {
  vomnibarUI: null,

  // sourceFrameId here (and below) is the ID of the frame from which this request originates, which
  // may be different from the current frame.

  activate(sourceFrameId, registryEntry) {
    const options = Object.assign({}, registryEntry.options, { completer: "omni" });
    this.open(sourceFrameId, options);
  },

  activateInNewTab(sourceFrameId, registryEntry) {
    const options = Object.assign({}, registryEntry.options, { completer: "omni", newTab: true });
    this.open(sourceFrameId, options);
  },

  activateTabSelection(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "tabs",
      selectFirst: true,
    });
  },

  activateBookmarks(sourceFrameId, registryEntry) {
    const options = Object.assign({}, registryEntry.options, {
      completer: "bookmarks",
      selectFirst: true,
    });
    this.open(sourceFrameId, options);
  },

  activateCommandSelection(sourceFrameId, registryEntry) {
    const options = Object.assign({}, registryEntry.options, {
      completer: "commands",
      selectFirst: true,
    });
    this.open(sourceFrameId, options);
  },

  activateBookmarksInNewTab(sourceFrameId, registryEntry) {
    const options = Object.assign({}, registryEntry.options, {
      completer: "bookmarks",
      selectFirst: true,
      newTab: true,
    });
    this.open(sourceFrameId, options);
  },

  activateEditUrl(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "omni",
      selectFirst: false,
      query: globalThis.location.href,
    });
  },

  activateEditUrlInNewTab(sourceFrameId) {
    this.open(sourceFrameId, {
      completer: "omni",
      selectFirst: false,
      query: globalThis.location.href,
      newTab: true,
    });
  },

  init() {
    if (!this.vomnibarUI) {
      this.vomnibarUI = new UIComponent();
      this.vomnibarUI.load("pages/vomnibar_page.html", "vomnibar-frame");
    }
  },

  // Opens the vomnibar.
  // - vomnibarShowOptions:
  //     completer: The name of the completer to fetch results from.
  //     query: Optional. Text to prefill the Vomnibar with.
  //     selectFirst: Optional. Whether to select the first entry.
  //     newTab: Optional. Whether to open the result in a new tab.
  //     keyword: A keyword which will scope the search to a UserSearchEngine.
  async open(sourceFrameId, vomnibarShowOptions) {
    this.init();
    // The Vomnibar cannot coexist with the help dialog (it causes focus issues).
    HelpDialog.abort();
    Utils.assertType(VomnibarShowOptions, vomnibarShowOptions);

    // Until the Vomnibar's iframe has loaded and taken the focus, keys go to the page. On the
    // Vomnibar's first use in a page, that takes long enough that a quick typist's first few keys
    // are lost, or run as Vimium commands. E.g. typing "w hello" would search for "ello" with the
    // default search engine, rather than for "hello" with the "w" search engine. So we capture
    // the text typed while the Vomnibar is loading, and pass it on.
    let typedText = "";
    let wasCancelled = false;
    const keyBuffer = new Mode();
    keyBuffer.init({
      name: "vomnibar/buffer-keys-while-loading",
      keydown: (event) => {
        if (KeyboardUtils.isEscape(event)) {
          wasCancelled = true;
        } else if (event.key.length == 1 && !event.ctrlKey && !event.metaKey) {
          typedText += event.key;
        }
        return handlerStack.suppressEvent;
      },
      keypress: () => handlerStack.suppressEvent,
      keyup: () => handlerStack.suppressEvent,
    });
    await this.vomnibarUI.iframePort;
    keyBuffer.exit();
    if (wasCancelled) {
      return;
    }

    this.vomnibarUI.show(
      Object.assign(vomnibarShowOptions, { name: "activate", typedText }),
      { sourceFrameId, focus: true },
    );
  },
};

globalThis.Vomnibar = Vomnibar;
