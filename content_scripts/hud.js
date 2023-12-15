//
// A heads-up-display (HUD) for showing Vimium page operations.
// Note: you cannot interact with the HUD until document.body is available.
//
const HUD = {
  tween: null,
  hudUI: null,
  findMode: null,
  abandon() {
    if (this.hudUI) {
      this.hudUI.hide(false);
    }
  },

  // Set by @pasteFromClipboard to handle the value returned by pasteResponse
  pasteListener: null,

  // This HUD is styled to precisely mimick the chrome HUD on Mac. Use the
  // "has_popup_and_link_hud.html" test harness to tweak these styles to match Chrome's. One
  // limitation of our HUD display is that it doesn't sit on top of horizontal scrollbars like
  // Chrome's HUD does.

  async init(focusable) {
    await Settings.onLoaded();
    if (focusable == null) {
      focusable = true;
    }
    if (this.hudUI == null) {
      const queryString = window.vimiumDomTestsAreRunning ? "?dom_tests=true" : "";
      this.hudUI = new UIComponent(`pages/hud.html${queryString}`, "vimiumHUDFrame", ({ data }) => {
        if (this[data.name]) {
          return this[data.name](data);
        }
      });
      // Allow to access to the clipboard through iframes.
      // This is only valid/necessary for Chrome. Firefox will show this console warning:
      // 'Feature Policy: Skipping unsupported feature name "clipboard-read"'
      if (!Utils.isFirefox()) {
        this.hudUI.iframeElement.allow = "clipboard-read; clipboard-write";
      }
    }
    // this[data.name]? data
    if (this.tween == null) {
      this.tween = new Tween(
        "iframe.vimiumHUDFrame.vimiumUIComponentVisible",
        this.hudUI.shadowDOM,
      );
    }
    if (focusable) {
      this.hudUI.toggleIframeElementClasses("vimiumNonClickable", "vimiumClickable");
      // Note(gdh1995): Chrome 74 only acknowledges text selection when a frame has been visible.
      // See more in #3277.
      // Note(mrmr1993): Show the HUD frame, so Firefox will actually perform the paste.
      this.hudUI.toggleIframeElementClasses("vimiumUIComponentHidden", "vimiumUIComponentVisible");
      // Force the re-computation of styles, so Chrome sends a visibility change message to the
      // child frame. See https://github.com/philc/vimium/pull/3277#issuecomment-487363284

      getComputedStyle(this.hudUI.iframeElement).display;
    } else {
      this.hudUI.toggleIframeElementClasses("vimiumClickable", "vimiumNonClickable");
    }
  },

  // duration - if omitted, the message will show until dismissed.
  show(text, duration) {
    DomUtils.documentComplete(async () => {
      clearTimeout(this._showForDurationTimerId);
      // @hudUI.activate will take charge of making it visible
      await this.init(false);
      this.hudUI.activate({ name: "show", text });
      this.tween.fade(1.0, 150);

      if (duration != null) {
        this._showForDurationTimerId = setTimeout(() => this.hide(), duration);
      }
    });
  },

  showFindMode(findMode = null) {
    this.findMode = findMode;
    DomUtils.documentComplete(async () => {
      await this.init();
      this.hudUI.activate({ name: "showFindMode" });
      this.tween.fade(1.0, 150);
    });
  },

  search(data) {
    // NOTE(mrmr1993): On Firefox, window.find moves the window focus away from the HUD. We use
    // postFindFocus to put it back, so the user can continue typing.
    this.findMode.findInPlace(data.query, {
      "postFindFocus": this.hudUI.iframeElement.contentWindow,
    });

    // Show the number of matches in the HUD UI.
    const matchCount = FindMode.query.parsedQuery.length > 0 ? FindMode.query.matchCount : 0;
    const showMatchText = FindMode.query.rawQuery.length > 0;
    this.hudUI.postMessage({ name: "updateMatchesCount", matchCount, showMatchText });
  },

  // Hide the HUD.
  // If :immediate is falsy, then the HUD is faded out smoothly (otherwise it is hidden
  // immediately).
  // If :updateIndicator is truthy, then we also refresh the mode indicator. The only time we don't
  // update the mode indicator, is when hide() is called for the mode indicator itself.
  hide(immediate, updateIndicator) {
    if (immediate == null) {
      immediate = false;
    }
    if (updateIndicator == null) {
      updateIndicator = true;
    }
    if ((this.hudUI != null) && (this.tween != null)) {
      clearTimeout(this._showForDurationTimerId);
      this.tween.stop();
      if (immediate) {
        if (updateIndicator) {
          Mode.setIndicator();
        } else {
          this.hudUI.hide();
        }
      } else {
        this.tween.fade(0, 150, () => this.hide(true, updateIndicator));
      }
    }
  },

  // These parameters describe the reason find mode is exiting, and come from the HUD UI component.
  hideFindMode({ exitEventIsEnter, exitEventIsEscape }) {
    let postExit;
    this.findMode.checkReturnToViewPort();

    // An element won't receive a focus event if the search landed on it while we were in the HUD
    // iframe. To end up with the correct modes active, we create a focus/blur event manually after
    // refocusing this window.
    window.focus();

    const focusNode = DomUtils.getSelectionFocusElement();
    if (document.activeElement != null) {
      document.activeElement.blur();
    }

    if (focusNode && focusNode.focus) {
      focusNode.focus();
    }

    if (exitEventIsEnter) {
      FindMode.handleEnter();
      if (FindMode.query.hasResults) {
        postExit = () => newPostFindMode();
      }
    } else if (exitEventIsEscape) {
      // We don't want FindMode to handle the click events that FindMode.handleEscape can generate,
      // so we wait until the mode is closed before running it.
      postExit = FindMode.handleEscape;
    }

    this.findMode.exit();
    if (postExit) {
      postExit();
    }
  },

  // These commands manage copying and pasting from the clipboard in the HUD frame.
  // NOTE(mrmr1993): We need this to copy and paste on Firefox:
  // * an element can't be focused in the background page, so copying/pasting doesn't work
  // * we don't want to disrupt the focus in the page, in case the page is listening for focus/blur
  // * events.
  // * the HUD shouldn't be active for this frame while any of the copy/paste commands are running.
  copyToClipboard(text) {
    DomUtils.documentComplete(async () => {
      await this.init();
      this.hudUI.postMessage({ name: "copyToClipboard", data: text });
    });
  },

  pasteFromClipboard(pasteListener) {
    this.pasteListener = pasteListener;
    DomUtils.documentComplete(async () => {
      await this.init();
      this.tween.fade(0, 0);
      this.hudUI.postMessage({ name: "pasteFromClipboard" });
    });
  },

  pasteResponse({ data }) {
    // Hide the HUD frame again.
    this.hudUI.toggleIframeElementClasses("vimiumUIComponentVisible", "vimiumUIComponentHidden");
    this.unfocusIfFocused();
    this.pasteListener(data);
  },

  unfocusIfFocused() {
    // On Firefox, if an <iframe> disappears when it's focused, then it will keep "focused", which
    // means keyboard events will always be dispatched to the HUD iframe
    if (this.hudUI && this.hudUI.showing) {
      this.hudUI.iframeElement.blur();
      window.focus();
    }
  },
};

class Tween {
  constructor(cssSelector, insertionPoint) {
    this.opacity = 0;
    this.intervalId = -1;
    this.styleElement = null;
    this.cssSelector = cssSelector;
    if (insertionPoint == null) insertionPoint = document.documentElement;
    this.styleElement = DomUtils.createElement("style");

    if (!this.styleElement.style) {
      // We're in an XML document, so we shouldn't inject any elements. See the comment in
      // UIComponent.
      Tween.prototype.fade = Tween.prototype.stop = Tween.prototype.updateStyle = function () {};
      return;
    }

    this.styleElement.type = "text/css";
    this.styleElement.innerHTML = "";
    insertionPoint.appendChild(this.styleElement);
  }

  fade(toAlpha, duration, onComplete) {
    clearInterval(this.intervalId);
    const startTime = (new Date()).getTime();
    const fromAlpha = this.opacity;
    const alphaStep = toAlpha - fromAlpha;

    const performStep = () => {
      const elapsed = (new Date()).getTime() - startTime;
      if (elapsed >= duration) {
        clearInterval(this.intervalId);
        this.updateStyle(toAlpha);
        if (onComplete) {
          onComplete();
        }
      } else {
        const value = ((elapsed / duration) * alphaStep) + fromAlpha;
        this.updateStyle(value);
      }
    };

    this.updateStyle(this.opacity);
    this.intervalId = setInterval(performStep, 50);
  }

  stop() {
    clearInterval(this.intervalId);
  }

  updateStyle(opacity) {
    this.opacity = opacity;
    this.styleElement.innerHTML = `\
${this.cssSelector} {
  opacity: ${this.opacity};
}\
`;
  }
}

window.HUD = HUD;
