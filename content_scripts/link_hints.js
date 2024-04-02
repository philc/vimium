//
// This implements link hinting. Typing "F" will enter link-hinting mode, where all clickable items
// on the page have a hint marker displayed containing a sequence of letters. Typing those letters
// will select a link.
//
// In our 'default' mode, the characters we use to show link hints are a user-configurable option.
// By default they're the home row. The CSS which is used on the link hints is also a configurable
// option.
//
// In 'filter' mode, our link hints are numbers, and the user can narrow down the range of
// possibilities by typing the text of the link itself.
//

// A DOM element that sits on top of a link, showing the key the user should type to select the
// link.
class HintMarker {
  hintDescriptor;
  localHint;
  linkText; // Used in FilterHints
  hintString; // Used in AlphabetHints
  markerRect; // Cached rectangle of the element, used for rotating hints.
  // Element is null if the hint marker reflects a hint that's owned by another frame.
  element;
  // Cached book-keeping when computing a marker's score against a query.
  linkWords;
  score;
  stableSortCount;
  constructor() {
    Object.seal(this);
  }
  isLocalMarker() {
    return this.localHint != null;
  }
}

// A clickable element in the current frame, plus metadata about how to show a hint marker for it.
class LocalHint {
  element; // The clickable element.
  image; // When element is an <area> (image map), `image` is its associated image.
  rect; // The rectangle where the hint should shown, to avoid overlapping with other hints.
  linkText; // Used in FilterHints.
  showLinkText; // Used in FilterHints.
  // The reason that an element has a link hint when the reason isn't obvious, e.g. the body of a
  // frame so that the frame can be focused. This reason is shown to the user in the hint's caption.
  reason;
  // "secondClassCitizen" means the element isn't clickable, but does have a tab index. We show
  // hints for these elements unless their hit box collides with another clickable element.
  secondClassCitizen;
  // An element that may be clickable based on our heuristics. It's a "false positive" if one of its
  // child elements is detected as clickable.
  possibleFalsePositive;
  constructor(o) {
    Object.seal(this);
    if (o) Object.assign(this, o);
  }
}

// Metadata about each LocalHint which is transferred to other frames in the current tab, so that
// every frame can be aware of every other frame's local hints.
class HintDescriptor {
  frameId; // The frameId that the hint is local to.
  localIndex; // An index into the owner frame's localHints.
  linkText; // The link's text. This is non-null only for FilterHints.
  constructor(o) {
    Object.seal(this);
    if (o) Object.assign(this, o);
  }
}

// The "name" property below is a short-form name to appear in the link-hints mode's name. It's for
// debug only.
//
const isMac = KeyboardUtils.platform === "Mac";
const OPEN_IN_CURRENT_TAB = {
  name: "curr-tab",
  indicator: "Open link in current tab",
};
const OPEN_IN_NEW_BG_TAB = {
  name: "bg-tab",
  indicator: "Open link in new tab",
  clickModifiers: { metaKey: isMac, ctrlKey: !isMac },
};
const OPEN_IN_NEW_FG_TAB = {
  name: "fg-tab",
  indicator: "Open link in new tab and switch to it",
  clickModifiers: { shiftKey: true, metaKey: isMac, ctrlKey: !isMac },
};
const OPEN_WITH_QUEUE = {
  name: "queue",
  indicator: "Open multiple links in new tabs",
  clickModifiers: { metaKey: isMac, ctrlKey: !isMac },
};
const COPY_LINK_URL = {
  name: "link",
  indicator: "Copy link URL to Clipboard",
  linkActivator(link) {
    if (link.href != null) {
      let url = link.href;
      if (url.slice(0, 7) === "mailto:") url = url.slice(7);
      HUD.copyToClipboard(url);
      if (28 < url.length) url = url.slice(0, 26) + "....";
      HUD.show(`Yanked ${url}`, 2000);
    } else {
      HUD.show("No link to yank.", 2000);
    }
  },
};
const OPEN_INCOGNITO = {
  name: "incognito",
  indicator: "Open link in incognito window",
  linkActivator(link) {
    chrome.runtime.sendMessage({ handler: "openUrlInIncognito", url: link.href });
  },
};
const DOWNLOAD_LINK_URL = {
  name: "download",
  indicator: "Download link URL",
  clickModifiers: { altKey: true, ctrlKey: false, metaKey: false },
};
const COPY_LINK_TEXT = {
  name: "copy-link-text",
  indicator: "Copy link text",
  linkActivator(link) {
    let text = link.textContent;
    if (text.length > 0) {
      HUD.copyToClipboard(text);
      if (28 < text.length) text = text.slice(0, 26) + "....";
      HUD.show(`Yanked ${text}`, 2000);
    } else {
      HUD.show("No text to yank.", 2000);
    }
  },
};
const HOVER_LINK = {
  name: "hover",
  indicator: "Hover link",
  linkActivator(link) {
    new HoverMode(link);
  },
};
const FOCUS_LINK = {
  name: "focus",
  indicator: "Focus link",
  linkActivator(link) {
    link.focus();
  },
};

const availableModes = [
  OPEN_IN_CURRENT_TAB,
  OPEN_IN_NEW_BG_TAB,
  OPEN_IN_NEW_FG_TAB,
  OPEN_WITH_QUEUE,
  COPY_LINK_URL,
  OPEN_INCOGNITO,
  DOWNLOAD_LINK_URL,
  COPY_LINK_TEXT,
  HOVER_LINK,
  FOCUS_LINK,
];

const HintCoordinator = {
  onExit: [],
  localHints: null,
  cacheAllKeydownEvents: null,

  // A WeakRef to the last clicked element. We track this so that we can mouse of it if the user
  // types ESC after clicking on it. See #3073.
  lastClickedElementRef: null,

  // Returns if the HintCoordinator will handle a given LinkHintsMessage.
  // Some messages will not be handled in the case where the help dialog is shown, and is then
  // hidden, but is still receiving link hints messages via broadcastLinkHintsMessage.
  willHandleMessage(messageType) {
    if (this.linkHintsMode) return true;
    return ["prepareToActivateMode", "activateMode", "getHintDescriptors", "exit"].includes(
      messageType,
    );
  },

  sendMessage(messageType, request) {
    if (request == null) request = {};
    request = Object.assign(request, { messageType, handler: "broadcastLinkHintsMessage" });
    chrome.runtime.sendMessage(request);
  },

  prepareToActivateMode(mode, onExit) {
    // We need to communicate with the background page (and other frames) to initiate link-hints
    // mode. To prevent other Vimium commands from being triggered before link-hints mode is
    // launched, we install a temporary mode to block (and cache) keyboard events.
    let cacheAllKeydownEvents;
    this.cacheAllKeydownEvents = cacheAllKeydownEvents = new CacheAllKeydownEvents({
      name: "link-hints/suppress-keyboard-events",
      singleton: "link-hints-mode",
      indicator: "Collecting hints...",
      exitOnEscape: true,
    });
    // FIXME(smblott) Global link hints is currently insufficiently reliable. If the mode above is
    // left in place, then Vimium blocks. As a temporary measure, we install a timer to remove it.
    // TODO(philc): I believe link hints is sufficiently reliable after the manifest V3 port
    // that this safeguard can now be removed.
    Utils.setTimeout(1000, function () {
      if (cacheAllKeydownEvents && cacheAllKeydownEvents.modeIsActive) {
        cacheAllKeydownEvents.exit();
      }
    });
    this.onExit = [onExit];
    chrome.runtime.sendMessage({
      handler: "prepareToActivateLinkHintsMode",
      modeIndex: availableModes.indexOf(mode),
      isVimiumHelpDialog: window.isVimiumHelpDialog,
      isVimiumOptionsPage: window.isVimiumOptionsPage,
    });
  },

  // Returns a list of HintDescriptors. Hint descriptors are global. They include all of the
  // information necessary for each frame to determine whether and when a hint from *any* frame is
  // selected.
  getHintDescriptors({ modeIndex, isVimiumHelpDialog }, _sender) {
    if (!DomUtils.isReady() || DomUtils.windowIsTooSmall()) return [];

    const requireHref = [COPY_LINK_URL, OPEN_INCOGNITO].includes(availableModes[modeIndex]);
    // If link hints is launched within the help dialog, then we only offer hints from that frame.
    // This improves the usability of the help dialog on the options page (particularly for
    // selecting command names).
    if (isVimiumHelpDialog && !window.isVimiumHelpDialog) {
      this.localHints = [];
    } else {
      this.localHints = LocalHints.getLocalHints(requireHref);
    }
    this.localHintDescriptors = this.localHints.map(({ linkText }, localIndex) => (
      new HintDescriptor({
        frameId,
        localIndex,
        linkText,
      })
    ));
    return this.localHintDescriptors;
  },

  // We activate LinkHintsMode() in every frame and provide every frame with exactly the same hint
  // descriptors. We also propagate the key state between frames. Therefore, the hint-selection
  // process proceeds in lock step in every frame, and this.linkHintsMode is in the same state in
  // every frame.
  activateMode({ frameId, frameIdToHintDescriptors, modeIndex, originatingFrameId }) {
    // We do not receive the frame's own hint descritors back from the background page. Instead, we
    // merge them with the hint descriptors from other frames here. Note that
    // this.localHintDescriptors can be null if "getHintDescriptors" failed in this frame when it
    // was last called, or if this frame didn't exist at the time that hints were requested.
    frameIdToHintDescriptors[frameId] = this.localHintDescriptors || [];
    this.localHintDescriptors = null;

    const hintDescriptors = Object.keys(frameIdToHintDescriptors)
      .sort()
      .flatMap((frame) => frameIdToHintDescriptors[frame]);

    if (this.cacheAllKeydownEvents?.modeIsActive) {
      this.cacheAllKeydownEvents.exit();
    }
    if (frameId !== originatingFrameId) {
      this.onExit = [];
    }
    this.linkHintsMode = new LinkHintsMode(hintDescriptors, availableModes[modeIndex]);
    // Replay keydown events which we missed (but for filtered hints only).
    if (Settings.get("filterLinkHints" && this.cacheAllKeydownEvents)) {
      this.cacheAllKeydownEvents.replayKeydownEvents();
    }
    this.cacheAllKeydownEvents = null;
  },

  // The following messages are exchanged between frames while link-hints mode is active.
  updateKeyState(request) {
    this.linkHintsMode.updateKeyState(request);
  },
  rotateHints() {
    this.linkHintsMode.rotateHints();
  },
  setOpenLinkMode({ modeIndex }) {
    this.linkHintsMode.setOpenLinkMode(availableModes[modeIndex], false);
  },
  activateActiveHintMarker() {
    this.linkHintsMode.activateLink(this.linkHintsMode.markerMatcher.activeHintMarker);
  },
  getLocalHint(hint) {
    return this.localHints[hint.localIndex];
  },

  exit({ isSuccess }) {
    if (this.linkHintsMode != null) {
      this.linkHintsMode.deactivateMode();
    }
    while (this.onExit.length > 0) {
      this.onExit.pop()(isSuccess);
    }
    this.linkHintsMode = this.localHints = null;
  },

  mouseOutOfLastClickedElement() {
    if (this.lastClickedElementRef == null) return;
    const el = this.lastClickedElementRef.deref();
    if (el) {
      DomUtils.simulateMouseEvent("mouseout", el, null);
    }
    this.lastClickedElementRef = null;
  },
};

const LinkHints = {
  activateMode(count, { mode, registryEntry }) {
    if (count == null) count = 1;
    if (mode == null) mode = OPEN_IN_CURRENT_TAB;

    switch (registryEntry?.options.action) {
      case "copy-text":
        mode = COPY_LINK_TEXT;
        break;
      case "hover":
        mode = HOVER_LINK;
        break;
      case "focus":
        mode = FOCUS_LINK;
        break;
    }

    if ((count > 0) || (mode === OPEN_WITH_QUEUE)) {
      HintCoordinator.prepareToActivateMode(mode, function (isSuccess) {
        if (isSuccess) {
          // Wait for the next tick to allow the previous mode to exit. It might yet generate a
          // click event, which would cause our new mode to exit immediately.
          Utils.nextTick(() => LinkHints.activateMode(count - 1, { mode }));
        }
      });
    }
  },

  activateModeToOpenInNewTab(count) {
    this.activateMode(count, { mode: OPEN_IN_NEW_BG_TAB });
  },
  activateModeToOpenInNewForegroundTab(count) {
    this.activateMode(count, { mode: OPEN_IN_NEW_FG_TAB });
  },
  activateModeToCopyLinkUrl(count) {
    this.activateMode(count, { mode: COPY_LINK_URL });
  },
  activateModeWithQueue() {
    this.activateMode(1, { mode: OPEN_WITH_QUEUE });
  },
  activateModeToOpenIncognito(count) {
    this.activateMode(count, { mode: OPEN_INCOGNITO });
  },
  activateModeToDownloadLink(count) {
    this.activateMode(count, { mode: DOWNLOAD_LINK_URL });
  },
};

class LinkHintsMode {
  // @mode: One of the enums listed at the top of this file.
  constructor(hintDescriptors, mode) {
    if (mode == null) mode = OPEN_IN_CURRENT_TAB;
    this.mode = mode;
    // We need documentElement to be ready in order to append links.
    if (!document.documentElement) return;

    this.hintMarkerContainingDiv = null;
    // Function that does the appropriate action on the selected link.
    this.linkActivator = undefined;
    // The link-hints "mode" (in the key-handler, indicator sense).
    this.hintMode = null;
    // A count of the number of Tab presses since the last non-Tab keyboard event.
    this.tabCount = 0;

    if (hintDescriptors.length === 0) {
      HUD.show("No links to select.", 2000);
      return;
    }

    // This count is used to rank equal-scoring hints when sorting, thereby making JavaScript's sort
    // stable.
    this.stableSortCount = 0;
    this.hintMarkers = hintDescriptors.map((desc) => this.createMarkerFor(desc));
    this.markerMatcher = Settings.get("filterLinkHints") ? new FilterHints() : new AlphabetHints();
    this.markerMatcher.fillInMarkers(this.hintMarkers, this.getNextZIndex.bind(this));

    this.hintMode = new Mode();
    this.hintMode.init({
      name: `hint/${this.mode.name}`,
      indicator: false,
      singleton: "link-hints-mode",
      suppressAllKeyboardEvents: true,
      suppressTrailingKeyEvents: true,
      exitOnEscape: true,
      exitOnClick: true,
      keydown: this.onKeyDownInMode.bind(this),
    });

    this.hintMode.onExit((event) => {
      const hintsWereCancelled = (event?.type === "click") ||
        ((event?.type === "keydown") &&
          (KeyboardUtils.isEscape(event) || KeyboardUtils.isBackspace(event)));
      if (hintsWereCancelled) {
        HintCoordinator.sendMessage("exit", { isSuccess: false });
      }
    });

    // Append these markers as top level children instead of as child nodes to the link itself,
    // because some clickable elements cannot contain children, e.g. submit buttons.
    this.hintMarkerContainingDiv = DomUtils.addElementsToPage(
      this.hintMarkers.filter((m) => m.isLocalMarker()).map((m) => m.element),
      { id: "vimiumHintMarkerContainer", className: "vimiumReset" },
    );

    // TODO(philc): 2024-03-27 Remove this hasPopoverSupport check once Firefox has popover support.
    // Also move this CSS into vimium.css.
    const hasPopoverSupport = this.hintMarkerContainingDiv.showPopover != null;
    if (hasPopoverSupport) {
      this.hintMarkerContainingDiv.popover = "manual";
      this.hintMarkerContainingDiv.showPopover();
      Object.assign(this.hintMarkerContainingDiv.style, {
        top: 0,
        left: 0,
        position: "absolute",
        // This display: block is required to override Github Enterprise's CSS circa 2024-04-01. See
        // #4446.
        display: "block",
        width: "100%",
        height: "100%",
        overflow: "visible",
      });
    }

    this.setIndicator();
  }

  // Increments and returns the Z index that should be used for the next hint marker on the page.
  getNextZIndex() {
    if (this.currentZIndex == null) {
      // This is the starting z-index value; it produces z-index values which are greater than all
      // of the other z-index values used by Vimium.
      this.currentZIndex = 2140000000;
    }
    return ++this.currentZIndex;
  }

  setOpenLinkMode(mode, shouldPropagateToOtherFrames) {
    this.mode = mode;
    if (shouldPropagateToOtherFrames == null) {
      shouldPropagateToOtherFrames = true;
    }
    if (shouldPropagateToOtherFrames) {
      HintCoordinator.sendMessage("setOpenLinkMode", {
        modeIndex: availableModes.indexOf(this.mode),
      });
    } else {
      this.setIndicator();
    }
  }

  setIndicator() {
    if (windowIsFocused()) {
      const typedCharacters = this.markerMatcher.linkTextKeystrokeQueue
        ? this.markerMatcher.linkTextKeystrokeQueue.join("")
        : "";
      const indicator = this.mode.indicator + (typedCharacters ? `: \"${typedCharacters}\"` : "") +
        ".";
      this.hintMode.setIndicator(indicator);
    }
  }

  // Creates a link marker for the given link.
  createMarkerFor(desc) {
    const marker = new HintMarker();
    const isLocalMarker = desc.frameId === frameId;
    if (isLocalMarker) {
      const localHint = HintCoordinator.getLocalHint(desc);
      const el = DomUtils.createElement("div");
      el.style.left = localHint.rect.left + "px";
      el.style.top = localHint.rect.top + "px";
      // Each hint marker is assigned a different z-index.
      el.style.zIndex = this.getNextZIndex();
      el.className = "vimiumReset internalVimiumHintMarker vimiumHintMarker";
      Object.assign(marker, {
        element: el,
        localHint,
      });
    }

    return Object.assign(marker, {
      hintDescriptor: desc,
      linkText: desc.linkText,
      stableSortCount: ++this.stableSortCount,
    });
  }

  // Handles all keyboard events.
  onKeyDownInMode(event) {
    if (event.repeat) return;

    // NOTE(smblott) The modifier behaviour here applies only to alphabet hints.
    if (
      ["Control", "Shift"].includes(event.key) && !Settings.get("filterLinkHints") &&
      [OPEN_IN_CURRENT_TAB, OPEN_WITH_QUEUE, OPEN_IN_NEW_BG_TAB, OPEN_IN_NEW_FG_TAB].includes(
        this.mode,
      )
    ) {
      // Toggle whether to open the link in a new or current tab.
      const previousMode = this.mode;
      const key = event.key;

      switch (key) {
        case "Shift":
          this.setOpenLinkMode(
            this.mode === OPEN_IN_CURRENT_TAB ? OPEN_IN_NEW_BG_TAB : OPEN_IN_CURRENT_TAB,
          );
          break;
        case "Control":
          this.setOpenLinkMode(
            this.mode === OPEN_IN_NEW_FG_TAB ? OPEN_IN_NEW_BG_TAB : OPEN_IN_NEW_FG_TAB,
          );
          break;
      }

      this.hintMode.push({
        keyup: (event) => {
          if (event.key === key) {
            handlerStack.remove();
            this.setOpenLinkMode(previousMode);
          }
          return true; // Continue bubbling the event.
        },
      });
    } else if (KeyboardUtils.isBackspace(event)) {
      if (this.markerMatcher.popKeyChar()) {
        this.tabCount = 0;
        this.updateVisibleMarkers();
      } else {
        // Exit via @hintMode.exit(), so that the LinkHints.activate() "onExit" callback sees the
        // key event and knows not to restart hints mode.
        this.hintMode.exit(event);
      }
    } else if (event.key === "Enter") {
      // Activate the active hint, if there is one.  Only FilterHints uses an active hint.
      if (this.markerMatcher.activeHintMarker) {
        HintCoordinator.sendMessage("activateActiveHintMarker");
      }
    } else if (event.key === "Tab") {
      if (event.shiftKey) {
        this.tabCount--;
      } else {
        this.tabCount++;
      }
      this.updateVisibleMarkers();
    } else if ((event.key === " ") && this.markerMatcher.shouldRotateHints(event)) {
      HintCoordinator.sendMessage("rotateHints");
    } else {
      if (!event.repeat) {
        let keyChar = Settings.get("filterLinkHints")
          ? KeyboardUtils.getKeyChar(event)
          : KeyboardUtils.getKeyChar(event).toLowerCase();
        if (keyChar) {
          if (keyChar === "space") {
            keyChar = " ";
          }
          if (keyChar.length === 1) {
            this.tabCount = 0;
            this.markerMatcher.pushKeyChar(keyChar);
            this.updateVisibleMarkers();
          } else {
            return handlerStack.suppressPropagation;
          }
        }
      }
    }

    return handlerStack.suppressEvent;
  }

  updateVisibleMarkers() {
    const { hintKeystrokeQueue, linkTextKeystrokeQueue } = this.markerMatcher;
    return HintCoordinator.sendMessage("updateKeyState", {
      hintKeystrokeQueue,
      linkTextKeystrokeQueue,
      tabCount: this.tabCount,
    });
  }

  updateKeyState({ hintKeystrokeQueue, linkTextKeystrokeQueue, tabCount }) {
    Object.assign(this.markerMatcher, { hintKeystrokeQueue, linkTextKeystrokeQueue });

    const { linksMatched, userMightOverType } = this.markerMatcher.getMatchingHints(
      this.hintMarkers,
      tabCount,
      this.getNextZIndex.bind(this),
    );
    if (linksMatched.length === 0) {
      this.deactivateMode();
    } else if (linksMatched.length === 1) {
      this.activateLink(linksMatched[0], userMightOverType);
    } else {
      for (const marker of this.hintMarkers) {
        this.hideMarker(marker);
      }
      for (const matched of linksMatched) {
        this.showMarker(matched, this.markerMatcher.hintKeystrokeQueue.length);
      }
    }

    return this.setIndicator();
  }

  markerOverlapsStack(marker, stack) {
    for (const otherMarker of stack) {
      if (Rect.intersects(marker.markerRect, otherMarker.markerRect)) {
        return true;
      }
    }
    return false;
  }

  // Rotate the hints' z-index values so that hidden hints become visible.
  rotateHints() {
    // Get local, visible hint markers.
    const localHintMarkers = this.hintMarkers.filter((m) =>
      m.isLocalMarker() && (m.element.style.display !== "none")
    );

    // Fill in the markers' rects, if necessary.
    for (const marker of localHintMarkers) {
      if (marker.markerRect == null) {
        marker.markerRect = marker.element.getClientRects()[0];
      }
    }

    // Calculate the overlapping groups of hints. We call each group a "stack". This is O(n^2).
    let stacks = [];
    for (const marker of localHintMarkers) {
      let stackForThisMarker = null;
      const results = [];
      for (const stack of stacks) {
        const markerOverlapsThisStack = this.markerOverlapsStack(marker, stack);
        if (markerOverlapsThisStack && (stackForThisMarker == null)) {
          // We've found an existing stack for this marker.
          stack.push(marker);
          stackForThisMarker = stack;
          results.push(stack);
        } else if (markerOverlapsThisStack && (stackForThisMarker != null)) {
          // This marker overlaps a second (or subsequent) stack; merge that stack into
          // stackForThisMarker and discard it.
          stackForThisMarker.push(...stack);
          continue; // Discard this stack.
        } else {
          stack; // Keep this stack.
          results.push(stack);
        }
      }
      stacks = results;

      if (stackForThisMarker == null) {
        stacks.push([marker]);
      }
    }

    // Rotate the z-indexes within each stack.
    for (const stack of stacks) {
      if (stack.length > 1) {
        const zIndexes = stack.map((marker) => marker.element.style.zIndex);
        zIndexes.push(zIndexes[0]);
        for (let index = 0; index < stack.length; index++) {
          const marker = stack[index];
          marker.element.style.zIndex = zIndexes[index + 1];
        }
      }
    }
  }

  // When only one hint remains, activate it in the appropriate way. The current frame may or may
  // not contain the matched link, and may or may not have the focus. The resulting four cases are
  // accounted for here by selectively pushing the appropriate HintCoordinator.onExit handlers.
  activateLink(linkMatched, userMightOverType) {
    let clickEl;
    if (userMightOverType == null) {
      userMightOverType = false;
    }
    this.removeHintMarkers();

    if (linkMatched.isLocalMarker()) {
      const localHint = linkMatched.localHint;
      clickEl = localHint.element;
      HintCoordinator.onExit.push((isSuccess) => {
        if (isSuccess) {
          if (localHint.reason === "Frame.") {
            return Utils.nextTick(() => focusThisFrame({ highlight: true }));
          } else if (localHint.reason === "Scroll.") {
            // Tell the scroller that this is the activated element.
            return handlerStack.bubbleEvent(Utils.isFirefox() ? "click" : "DOMActivate", {
              target: clickEl,
            });
          } else if (localHint.reason === "Open.") {
            return clickEl.open = !clickEl.open;
          } else if (DomUtils.isSelectable(clickEl)) {
            window.focus();
            return DomUtils.simulateSelect(clickEl);
          } else {
            const clickActivator = (modifiers) => (link) => DomUtils.simulateClick(link, modifiers);
            const linkActivator = this.mode.linkActivator != null
              ? this.mode.linkActivator
              : clickActivator(this.mode.clickModifiers);
            // Note(gdh1995): Here we should allow special elements to get focus,
            // <select>: latest Chrome refuses `mousedown` event, and we can only focus it to let
            //     user press space to activate the popup menu
            // <object> & <embed>: for Flash games which have their own key event handlers since we
            //     have been able to blur them by pressing `Escape`
            if (["input", "select", "object", "embed"].includes(clickEl.nodeName.toLowerCase())) {
              clickEl.focus();
            }
            HintCoordinator.lastClickedElementRef = new WeakRef(clickEl);
            return linkActivator(clickEl);
          }
        }
      });
    }

    // If flash elements are created, then this function can be used later to remove them.
    let removeFlashElements = function () {};
    if (linkMatched.isLocalMarker()) {
      const { top: viewportTop, left: viewportLeft } = DomUtils.getViewportTopLeft();
      const flashElements = Array.from(clickEl.getClientRects()).map((rect) =>
        DomUtils.addFlashRect(Rect.translate(rect, viewportLeft, viewportTop))
      );
      removeFlashElements = () => flashElements.map((flashEl) => DomUtils.removeElement(flashEl));
    }

    // If we're using a keyboard blocker, then the frame with the focus sends the "exit" message,
    // otherwise the frame containing the matched link does.
    if (userMightOverType) {
      HintCoordinator.onExit.push(removeFlashElements);
      if (windowIsFocused()) {
        const callback = (isSuccess) => HintCoordinator.sendMessage("exit", { isSuccess });
        return Settings.get("waitForEnterForFilteredHints")
          ? new WaitForEnter(callback)
          : new TypingProtector(200, callback);
      }
    } else if (linkMatched.isLocalMarker()) {
      Utils.setTimeout(400, removeFlashElements);
      return HintCoordinator.sendMessage("exit", { isSuccess: true });
    }
  }

  // Shows the marker, highlighting matchingCharCount characters.
  showMarker(linkMarker, matchingCharCount) {
    if (!linkMarker.isLocalMarker()) return;

    linkMarker.element.style.display = "";
    for (let j = 0, end = linkMarker.element.childNodes.length; j < end; j++) {
      if (j < matchingCharCount) {
        linkMarker.element.childNodes[j].classList.add("matchingCharacter");
      } else {
        linkMarker.element.childNodes[j].classList.remove("matchingCharacter");
      }
    }
  }

  hideMarker(marker) {
    if (marker.isLocalMarker()) {
      marker.element.style.display = "none";
    }
  }

  deactivateMode() {
    this.removeHintMarkers();
    if (this.hintMode != null) this.hintMode.exit();
  }

  removeHintMarkers() {
    if (this.hintMarkerContainingDiv) {
      DomUtils.removeElement(this.hintMarkerContainingDiv);
    }
    this.hintMarkerContainingDiv = null;
  }
}

// Use characters for hints, and do not filter links by their text.
class AlphabetHints {
  constructor() {
    this.linkHintCharacters = Settings.get("linkHintCharacters").toLowerCase();
    this.hintKeystrokeQueue = [];
  }

  fillInMarkers(hintMarkers) {
    const hintStrings = this.hintStrings(hintMarkers.length);
    if (hintMarkers.length != hintStrings.length) {
      // This can only happen if the user's linkHintCharacters setting is empty.
      console.warn("Unable to generate link hint strings.");
    } else {
      for (let i = 0; i < hintMarkers.length; i++) {
        const marker = hintMarkers[i];
        marker.hintString = hintStrings[i];
        if (marker.isLocalMarker()) {
          marker.element.innerHTML = spanWrap(marker.hintString.toUpperCase());
        }
      }
    }
  }

  //
  // Returns a list of hint strings which will uniquely identify the given number of links. The hint
  // strings may be of different lengths.
  //
  hintStrings(linkCount) {
    if (this.linkHintCharacters.length == 0) return [];
    let hints = [""];
    let offset = 0;
    while (((hints.length - offset) < linkCount) || (hints.length === 1)) {
      const hint = hints[offset++];
      for (const ch of this.linkHintCharacters) {
        hints.push(ch + hint);
      }
    }
    hints = hints.slice(offset, offset + linkCount);

    // Shuffle the hints so that they're scattered; hints starting with the same character and short
    // hints are spread evenly throughout the array.
    return hints.sort().map((str) => str.reverse());
  }

  getMatchingHints(hintMarkers) {
    const matchString = this.hintKeystrokeQueue.join("");
    return {
      linksMatched: hintMarkers.filter((m) => m.hintString.startsWith(matchString)),
    };
  }

  pushKeyChar(keyChar) {
    this.hintKeystrokeQueue.push(keyChar);
  }

  popKeyChar() {
    return this.hintKeystrokeQueue.pop();
  }

  // For alphabet hints, <Space> always rotates the hints, regardless of modifiers.
  shouldRotateHints() {
    return true;
  }
}

// Use characters for hints, and also filter links by their text.
class FilterHints {
  constructor() {
    this.linkHintNumbers = Settings.get("linkHintNumbers").toUpperCase();
    this.hintKeystrokeQueue = [];
    this.linkTextKeystrokeQueue = [];
    this.activeHintMarker = null;
    // The regexp for splitting typed text and link texts. We split on sequences of non-word
    // characters and link-hint numbers.
    this.splitRegexp = new RegExp(
      `[\\W${Utils.escapeRegexSpecialCharacters(this.linkHintNumbers)}]+`,
    );
  }

  generateHintString(linkHintNumber) {
    const base = this.linkHintNumbers.length;
    const hint = [];
    while (linkHintNumber > 0) {
      hint.push(this.linkHintNumbers[Math.floor(linkHintNumber % base)]);
      linkHintNumber = Math.floor(linkHintNumber / base);
    }
    return hint.reverse().join("");
  }

  // Populates the marker's element with the correct caption.
  renderMarker(marker) {
    let linkText = marker.linkText;
    if (linkText.length > 35) {
      linkText = linkText.slice(0, 33) + "...";
    }
    const caption = marker.hintString + (marker.localHint.showLinkText ? ": " + linkText : "");
    marker.element.innerHTML = spanWrap(caption);
  }

  fillInMarkers(hintMarkers, getNextZIndex) {
    for (const marker of hintMarkers) {
      if (marker.isLocalMarker()) {
        this.renderMarker(marker);
      }
    }

    // We use getMatchingHints() here (although we know that all of the hints will match) to get an
    // order on the hints and highlight the first one.
    return this.getMatchingHints(hintMarkers, 0, getNextZIndex);
  }

  getMatchingHints(hintMarkers, tabCount, getNextZIndex) {
    // At this point, linkTextKeystrokeQueue and hintKeystrokeQueue have been updated to reflect the
    // latest input. Use them to filter the link hints accordingly.
    const matchString = this.hintKeystrokeQueue.join("");
    let linksMatched = this.filterLinkHints(hintMarkers);
    linksMatched = linksMatched.filter((linkMarker) =>
      linkMarker.hintString.startsWith(matchString)
    );

    // Visually highlight the active hint (that is, the one that will be activated if the user types
    // <Enter>).
    tabCount = ((linksMatched.length * Math.abs(tabCount)) + tabCount) % linksMatched.length;

    if (this.activeHintMarker?.element) {
      this.activeHintMarker.element.classList.remove("vimiumActiveHintMarker");
    }

    this.activeHintMarker = linksMatched[tabCount];

    if (this.activeHintMarker?.element) {
      this.activeHintMarker.element.classList.add("vimiumActiveHintMarker");
      this.activeHintMarker.element.style.zIndex = getNextZIndex();
    }

    return {
      linksMatched,
      userMightOverType: (this.hintKeystrokeQueue.length === 0) &&
        (this.linkTextKeystrokeQueue.length > 0),
    };
  }

  pushKeyChar(keyChar) {
    if (this.linkHintNumbers.indexOf(keyChar) >= 0) {
      this.hintKeystrokeQueue.push(keyChar);
    } else if (
      (keyChar.toLowerCase() !== keyChar) &&
      (this.linkHintNumbers.toLowerCase() !== this.linkHintNumbers.toUpperCase())
    ) {
      // The the keyChar is upper case and the link hint "numbers" contain characters (e.g.
      // [a-zA-Z]). We don't want some upper-case letters matching hints (above) and some matching
      // text (below), so we ignore such keys.
      return;
      // We only accept <Space> and characters which are not used for splitting (e.g. "a", "b",
      // etc., but not "-").
    } else if ((keyChar === " ") || !this.splitRegexp.test(keyChar)) {
      // Since we might renumber the hints, we should reset the current hintKeyStrokeQueue.
      this.hintKeystrokeQueue = [];
      this.linkTextKeystrokeQueue.push(keyChar.toLowerCase());
    }
  }

  popKeyChar() {
    return this.hintKeystrokeQueue.pop() || this.linkTextKeystrokeQueue.pop();
  }

  // Filter link hints by search string, renumbering the hints as necessary.
  filterLinkHints(hintMarkers) {
    const scoreFunction = this.scoreLinkHint(this.linkTextKeystrokeQueue.join(""));
    const matchingHintMarkers = hintMarkers
      .filter((linkMarker) => {
        linkMarker.score = scoreFunction(linkMarker);
        return (this.linkTextKeystrokeQueue.length === 0) || (linkMarker.score > 0);
      }).sort(function (a, b) {
        if (b.score === a.score) return b.stableSortCount - a.stableSortCount;
        else return b.score - a.score;
      });

    if (
      (matchingHintMarkers.length === 0) && (this.hintKeystrokeQueue.length === 0) &&
      (this.linkTextKeystrokeQueue.length > 0)
    ) {
      // We don't accept typed text which doesn't match any hints.
      this.linkTextKeystrokeQueue.pop();
      return this.filterLinkHints(hintMarkers);
    } else {
      let linkHintNumber = 1;
      return matchingHintMarkers.map((m) => {
        m.hintString = this.generateHintString(linkHintNumber++);
        if (m.isLocalMarker()) this.renderMarker(m);
        return m;
      });
    }
  }

  // Assign a score to a filter match (higher is better). We assign a higher score for matches at
  // the start of a word, and a considerably higher score still for matches which are whole words.
  scoreLinkHint(linkSearchString) {
    const searchWords = linkSearchString.trim().toLowerCase().split(this.splitRegexp);
    return (linkMarker) => {
      if (!(searchWords.length > 0)) return 0;

      // We only keep non-empty link words. Empty link words cannot be matched, and leading empty
      // link words disrupt the scoring of matches at the start of the text.
      if (!linkMarker.linkWords) {
        linkMarker.linkWords = linkMarker.linkText.toLowerCase().split(this.splitRegexp).filter(
          (term) => term,
        );
      }

      const linkWords = linkMarker.linkWords;

      const searchWordScores = searchWords.map((searchWord) => {
        const linkWordScores = linkWords.map((linkWord, idx) => {
          const position = linkWord.indexOf(searchWord);
          if (position < 0) {
            return 0; // No match.
          } else if ((position === 0) && (searchWord.length === linkWord.length)) {
            if (idx === 0) return 8;
            else return 4; // Whole-word match.
          } else if (position === 0) {
            if (idx === 0) return 6;
            else return 2; // Match at the start of a word.
          } else {
            return 1;
          }
        }); // 0 < position; other match.

        return Math.max(...linkWordScores);
      });

      if (searchWordScores.includes(0)) {
        return 0;
      } else {
        const addFunc = (a, b) => a + b;
        const score = searchWordScores.reduce(addFunc, 0);
        // Prefer matches in shorter texts. To keep things balanced for links without any text, we
        // just weight them as if their length was 100 (so, quite long).
        return score / Math.log(1 + (linkMarker.linkText.length || 100));
      }
    };
  }

  // For filtered hints, we require a modifier (because <Space> on its own is a token separator).
  shouldRotateHints(event) {
    return event.ctrlKey || event.altKey || event.metaKey || event.shiftKey;
  }
}

//
// Make each hint character a span, so that we can highlight the typed characters as you type them.
//
const spanWrap = (hintString) => {
  const innerHTML = [];
  for (const char of hintString) {
    innerHTML.push("<span class='vimiumReset'>" + char + "</span>");
  }
  return innerHTML.join("");
};

const LocalHints = {
  // Returns an array of LocalHints if the element is visible and clickable, and computes the rect
  // which bounds this element in the viewport. We return an array because there may be more than
  // one part of element which is clickable (for example, if it's an image); if so, each LocalHint
  // represents one of the clickable rectangles of the element.
  getLocalHintsForElement(element) {
    // Get the tag name. However, `element.tagName` can be an element (not a string, see #2035), so
    // we guard against that.
    const tagName = element.tagName.toLowerCase?.() || "";
    let isClickable = false;
    let onlyHasTabIndex = false;
    let possibleFalsePositive = false;
    const hints = [];
    const imageMapAreas = [];
    let reason = null;

    // Insert area elements that provide click functionality to an img.
    if (tagName === "img") {
      let mapName = element.getAttribute("usemap");
      if (mapName) {
        const imgClientRects = element.getClientRects();
        mapName = mapName.replace(/^#/, "").replace('"', '\\"');
        const map = document.querySelector(`map[name=\"${mapName}\"]`);
        if (map && (imgClientRects.length > 0)) {
          isClickable = true;
          const areas = map.getElementsByTagName("area");
          let areasAndRects = DomUtils.getClientRectsForAreas(imgClientRects[0], areas);
          // We use this image property when detecting overlapping links.
          areasAndRects = areasAndRects.map((o) => Object.assign(o, { image: element }));
          imageMapAreas.push(...areasAndRects);
        }
      }
    }

    // Check aria properties to see if the element should be ignored.
    // Note that we're showing hints for elements with aria-hidden=true. See #3501 for discussion.
    const ariaDisabled = element.getAttribute("aria-disabled");
    if (ariaDisabled && ["", "true"].includes(ariaDisabled.toLowerCase())) {
      return []; // This element should never have a link hint.
    }

    // Check for AngularJS listeners on the element.
    if (!this.checkForAngularJs) {
      this.checkForAngularJs = (function () {
        const angularElements = document.getElementsByClassName("ng-scope");
        if (angularElements.length === 0) {
          return () => false;
        } else {
          const ngAttributes = [];
          for (const prefix of ["", "data-", "x-"]) {
            for (const separator of ["-", ":", "_"]) {
              ngAttributes.push(`${prefix}ng${separator}click`);
            }
          }
          return function (element) {
            for (const attribute of ngAttributes) {
              if (element.hasAttribute(attribute)) return true;
            }
            return false;
          };
        }
      })();
    }

    if (!isClickable) isClickable = this.checkForAngularJs(element);

    if (element.hasAttribute("onclick")) {
      isClickable = true;
    } else {
      const role = element.getAttribute("role");
      const clickableRoles = [
        "button",
        "tab",
        "link",
        "checkbox",
        "menuitem",
        "menuitemcheckbox",
        "menuitemradio",
        "radio",
      ];
      if (role != null && clickableRoles.includes(role.toLowerCase())) {
        isClickable = true;
      } else {
        const contentEditable = element.getAttribute("contentEditable");
        if (
          contentEditable != null &&
          ["", "contenteditable", "true"].includes(contentEditable.toLowerCase())
        ) {
          isClickable = true;
        }
      }
    }

    // Check for jsaction event listeners on the element.
    if (!isClickable && element.hasAttribute("jsaction")) {
      const jsactionRules = element.getAttribute("jsaction").split(";");
      for (const jsactionRule of jsactionRules) {
        const ruleSplit = jsactionRule.trim().split(":");
        if ((ruleSplit.length >= 1) && (ruleSplit.length <= 2)) {
          const [eventType, namespace, actionName] = ruleSplit.length === 1
            ? ["click", ...ruleSplit[0].trim().split("."), "_"]
            : [ruleSplit[0], ...ruleSplit[1].trim().split("."), "_"];
          if (!isClickable) {
            isClickable = (eventType === "click") && (namespace !== "none") && (actionName !== "_");
          }
        }
      }
    }

    // Check for tagNames which are natively clickable.
    switch (tagName) {
      case "a":
        isClickable = true;
        break;
      case "textarea":
        isClickable ||= !element.disabled && !element.readOnly;
        break;
      case "input":
        isClickable ||= !((element.getAttribute("type")?.toLowerCase() == "hidden") ||
          element.disabled ||
          (element.readOnly && DomUtils.isSelectable(element)));
        break;
      case "button":
      case "select":
        isClickable ||= !element.disabled;
        break;
      case "object":
      case "embed":
        isClickable = true;
        break;
      case "label":
        isClickable ||= (element.control != null) &&
          !element.control.disabled &&
          ((this.getLocalHintsForElement(element.control)).length === 0);
        break;
      case "body":
        isClickable ||= (element === document.body) && !windowIsFocused() &&
            (window.innerWidth > 3) && (window.innerHeight > 3) &&
            ((document.body != null ? document.body.tagName.toLowerCase() : undefined) !==
              "frameset")
          ? (reason = "Frame.")
          : undefined;
        isClickable ||= (element === document.body) && windowIsFocused() &&
            Scroller.isScrollableElement(element)
          ? (reason = "Scroll.")
          : undefined;
        break;
      case "img":
        isClickable ||= ["zoom-in", "zoom-out"].includes(element.style.cursor);
        break;
      case "div":
      case "ol":
      case "ul":
        isClickable ||=
          (element.clientHeight < element.scrollHeight) && Scroller.isScrollableElement(element)
            ? (reason = "Scroll.")
            : undefined;
        break;
      case "details":
        isClickable = true;
        reason = "Open.";
        break;
    }

    // NOTE(smblott) Disabled pending resolution of #2997.
    // # Detect elements with "click" listeners installed with `addEventListener()`.
    // isClickable ||= element.hasAttribute "_vimium-has-onclick-listener"

    // An element with a class name containing the text "button" might be clickable. However, real
    // clickables are often wrapped in elements with such class names. So, when we find clickables
    // based only on their class name, we mark them as unreliable.
    const className = element.getAttribute("class");
    if (!isClickable && className?.toLowerCase().includes("button")) {
      isClickable = true;
      possibleFalsePositive = true;
    }

    // Elements with tabindex are sometimes useful, but usually not. We can treat them as second
    // class citizens when it improves UX, so take special note of them.
    const tabIndexValue = element.getAttribute("tabindex");
    const tabIndex = tabIndexValue ? parseInt(tabIndexValue) : -1;
    if (!isClickable && !(tabIndex < 0) && !isNaN(tabIndex)) {
      isClickable = true;
      onlyHasTabIndex = true;
    }

    if (isClickable) {
      // An image map has multiple clickable areas, and so can represent multiple LocalHints.
      if (imageMapAreas.length > 0) {
        const mapHints = imageMapAreas.map((areaAndRect) => {
          return new LocalHint({
            element: areaAndRect.element,
            image: element,
            // element,
            rect: areaAndRect.rect,
            secondClassCitizen: onlyHasTabIndex,
            possibleFalsePositive,
            reason,
          });
        });
        hints.push(...mapHints);
      } else {
        const clientRect = DomUtils.getVisibleClientRect(element, true);
        if (clientRect !== null) {
          const hint = new LocalHint({
            element,
            rect: clientRect,
            secondClassCitizen: onlyHasTabIndex,
            possibleFalsePositive,
            reason,
          });
          hints.push(hint);
        }
      }
    }

    return hints;
  },

  //
  // Returns element at a given (x,y) with an optional root element.
  // If the returned element is a shadow root, descend into that shadow root recursively until we
  // hit an actual element.
  getElementFromPoint(x, y, root, stack) {
    if (root == null) root = document;
    if (stack == null) stack = [];
    const element = root.elementsFromPoint
      ? root.elementsFromPoint(x, y)[0]
      : root.elementFromPoint(x, y);

    if (stack.includes(element)) return element;

    stack.push(element);

    if (element && element.shadowRoot) {
      return LocalHints.getElementFromPoint(x, y, element.shadowRoot, stack);
    }

    return element;
  },

  // Returns an array of LocalHints representing all clickable elements that are not hidden and are
  // in the current viewport, along with rectangles at which (parts of) the elements are displayed.
  // In the process, we try to find rects where elements do not overlap so that link hints are
  // unambiguous. Because of this, the rects returned will frequently *NOT* be equivalent to the
  // rects for the whole element.
  // - requireHref: true if the hintable element must have an href, because an href is required for
  //   commands like "LinkHints.activateModeToCopyLinkUrl".
  getLocalHints(requireHref) {
    // We need documentElement to be ready in order to find links.
    if (!document.documentElement) return [];

    // Find all elements, recursing into shadow DOM if present.
    const getAllElements = (root, elements) => {
      if (elements == null) elements = [];
      for (const element of Array.from(root.querySelectorAll("*"))) {
        elements.push(element);
        if (element.shadowRoot) {
          getAllElements(element.shadowRoot, elements);
        }
      }
      return elements;
    };

    const elements = getAllElements(document.documentElement);
    let localHints = [];

    // The order of elements here is important; they should appear in the order they are in the DOM,
    // so that we can work out which element is on top when multiple elements overlap. Detecting
    // elements in this loop is the sensible, efficient way to ensure this happens.
    // NOTE(mrmr1993): Our previous method (combined XPath and DOM traversal for jsaction) couldn't
    // provide this, so it's necessary to check whether elements are clickable in order, as we do
    // below.
    for (const element of Array.from(elements)) {
      if (!requireHref || !!element.href) {
        const hints = this.getLocalHintsForElement(element);
        localHints.push(...hints);
      }
    }

    // Traverse the DOM from descendants to ancestors, so later elements show above earlier elements.
    localHints = localHints.reverse();

    // Filter out suspected false positives. A false positive is taken to be an element marked as a
    // possible false positive for which a close descendant is already clickable. False positives
    // tend to be close together in the DOM, so - to keep the cost down - we only search nearby
    // elements. NOTE(smblott): The visible elements have already been reversed, so we're visiting
    // descendants before their ancestors.
    // This determines how many descendants we're willing to consider.
    const descendantsToCheck = [1, 2, 3];
    localHints = localHints.filter((hint, position) => {
      if (!hint.possibleFalsePositive) return true;
      // Determine if the clickable element is indeed a false positive.
      const lookbackWindow = 6;
      let index = Math.max(0, position - lookbackWindow);
      while (index < position) {
        let candidateDescendant = localHints[index].element;
        for (const _ of descendantsToCheck) {
          candidateDescendant = candidateDescendant?.parentElement;
          if (candidateDescendant === hint.element) {
            // This is a false positive; exclude it from visibleElements.
            return false;
          }
        }
        index += 1;
      }
      return true;
    });

    // This loop will check if any corner or center of element is clickable.
    // document.elementFromPoint will find an element at a x,y location.
    // Node.contain checks to see if an element contains another. note: someNode.contains(someNode)
    // === true. If we do not find our element as a descendant of any element we find, assume it's
    // completely covered.

    const nonOverlappingHints = localHints.filter((hint) => {
      if (hint.secondClassCitizen) return false;
      const rect = hint.rect;

      // Check middle of element first, as this is perhaps most likely to return true.
      const elementFromMiddlePoint = LocalHints.getElementFromPoint(
        rect.left + (rect.width * 0.5),
        rect.top + (rect.height * 0.5),
      );
      const hasIntersection = elementFromMiddlePoint &&
        (hint.element.contains(elementFromMiddlePoint) ||
          elementFromMiddlePoint.contains(hint.element));
      if (hasIntersection) return true;

      // Handle image maps
      if (hint.element.localName == "area" && elementFromMiddlePoint == hint.image) {
        return true;
      }

      // If not in middle, try corners.
      // Adjusting the rect by 0.1 towards the upper left, which empirically fixes some cases where
      // another element would've been found instead. NOTE(philc): This isn't well explained.
      // Originated in #2251.
      const verticalCoords = [rect.top + 0.1, rect.bottom - 0.1];
      const horizontalCoords = [rect.left + 0.1, rect.right - 0.1];

      for (const verticalCoord of verticalCoords) {
        for (const horizontalCoord of horizontalCoords) {
          const elementFromPoint = LocalHints.getElementFromPoint(horizontalCoord, verticalCoord);
          const hasIntersection = elementFromPoint &&
            (hint.element.contains(elementFromPoint) || elementFromPoint.contains(hint.element));
          if (hasIntersection) return true;
        }
      }
    });

    nonOverlappingHints.reverse();

    // Position the rects within the window.
    const { top, left } = DomUtils.getViewportTopLeft();
    for (const hint of nonOverlappingHints) {
      hint.rect.top += top;
      hint.rect.left += left;
    }

    if (Settings.get("filterLinkHints")) {
      for (const hint of nonOverlappingHints) {
        Object.assign(hint, this.generateLinkText(hint));
      }
    }
    return nonOverlappingHints;
  },

  generateLinkText(hint) {
    const element = hint.element;
    let linkText = "";
    let showLinkText = false;
    // toLowerCase is necessary as html documents return "IMG" and xhtml documents return "img"
    const nodeName = element.nodeName.toLowerCase();

    if (nodeName === "input") {
      if ((element.labels != null) && (element.labels.length > 0)) {
        linkText = element.labels[0].textContent.trim();
        // Remove trailing ":" commonly found in labels.
        if (linkText[linkText.length - 1] === ":") {
          linkText = linkText.slice(0, linkText.length - 1);
        }
        showLinkText = true;
      } else if ((element.getAttribute("type") || "").toLowerCase() === "file") {
        linkText = "Choose File";
      } else if (element.type !== "password") {
        linkText = element.value;
        if (!linkText && "placeholder" in element) {
          linkText = element.placeholder;
        }
      }
      // Check if there is an image embedded in the <a> tag.
    } else if (
      (nodeName === "a") && !element.textContent.trim() &&
      element.firstElementChild &&
      (element.firstElementChild.nodeName.toLowerCase() === "img")
    ) {
      linkText = element.firstElementChild.alt || element.firstElementChild.title;
      if (linkText) {
        showLinkText = true;
      }
    } else if (hint.reason != null) {
      linkText = hint.reason;
      showLinkText = true;
    } else if (element.textContent.length > 0) {
      linkText = element.textContent.slice(0, 256);
    } else if (element.hasAttribute("title")) {
      linkText = element.getAttribute("title");
    } else {
      linkText = element.innerHTML.slice(0, 256);
    }

    return { linkText: linkText.trim(), showLinkText };
  },
};

// Suppress all keyboard events until the user stops typing for sufficiently long.
class TypingProtector extends Mode {
  constructor(delay, callback) {
    super();
    this.init({
      name: "hint/typing-protector",
      suppressAllKeyboardEvents: true,
      keydown: resetExitTimer,
      keypress: resetExitTimer,
    });

    this.timer = Utils.setTimeout(delay, () => this.exit());

    const resetExitTimer = () => {
      clearTimeout(this.timer);
      this.timer = Utils.setTimeout(delay, () => this.exit());
    };

    this.onExit(() => callback(true)); // true -> isSuccess.
  }
}

class WaitForEnter extends Mode {
  constructor(callback) {
    super();
    this.init({
      name: "hint/wait-for-enter",
      suppressAllKeyboardEvents: true,
      indicator: "Hit <Enter> to proceed...",
    });

    this.push({
      keydown: (event) => {
        if (event.key === "Enter") {
          this.exit();
          return callback(true); // true -> isSuccess.
        } else if (KeyboardUtils.isEscape(event)) {
          this.exit();
          return callback(false);
        }
      },
    }); // false -> isSuccess.
  }
}

class HoverMode extends Mode {
  constructor(link) {
    super();
    super.init({ name: "hover-mode", singleton: "hover-mode", exitOnEscape: true });
    this.link = link;
    DomUtils.simulateHover(this.link);
    this.onExit(() => DomUtils.simulateUnhover(this.link));
  }
}

Object.assign(window, {
  LinkHints,
  HintCoordinator,
  // Exported for tests.
  LinkHintsMode,
  LocalHints,
  AlphabetHints,
  WaitForEnter,
});
