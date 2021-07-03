class InsertMode extends Mode {
  constructor(options) {
    super();
    if (options == null)
      options = {};

    // There is one permanently-installed instance of InsertMode.  It tracks focus changes and
    // activates/deactivates itself (by setting @insertModeLock) accordingly.
    this.permanent = options.permanent;

    // If truthy, then we were activated by the user (with "i").
    this.global = options.global;

    const handleKeyEvent = event => {
      if (!this.isActive(event))
        return this.continueBubbling;

      // See comment here: https://github.com/philc/vimium/commit/48c169bd5a61685bb4e67b1e76c939dbf360a658.
      const activeElement = this.getActiveElement();
      if ((activeElement === document.body) && activeElement.isContentEditable)
        return this.passEventToPage;

      // Check for a pass-next-key key.
      const keyString = KeyboardUtils.getKeyCharString(event);
      if (Settings.get("passNextKeyKeys").includes(keyString)) {
        new PassNextKeyMode();
      } else if ((event.type === 'keydown') && KeyboardUtils.isEscape(event)) {
        if (DomUtils.isFocusable(activeElement))
          activeElement.blur();

        if (!this.permanent)
          this.exit();

      } else {
        return this.passEventToPage;
      }

      return this.suppressEvent;
    };

    const defaults = {
      name: "insert",
      indicator: !this.permanent && !Settings.get("hideHud")  ? "Insert mode" : null,
      keypress: handleKeyEvent,
      keydown: handleKeyEvent
    };

    super.init(Object.assign(defaults, options));

    // Only for tests.  This gives us a hook to test the status of the permanently-installed instance.
    if (this.permanent)
      InsertMode.permanentInstance = this;
  }

  isActive(event) {
    if (event === InsertMode.suppressedEvent)
      return false;
    if (this.global)
      return true;
    return DomUtils.isFocusable(this.getActiveElement());
  }

  getActiveElement() {
    let activeElement = document.activeElement;
    while (activeElement && activeElement.shadowRoot && activeElement.shadowRoot.activeElement)
      activeElement = activeElement.shadowRoot.activeElement;
    return activeElement;
  }

  static suppressEvent(event) { return this.suppressedEvent = event; }
}

// This allows PostFindMode to suppress the permanently-installed InsertMode instance.
InsertMode.suppressedEvent = null;

// This implements the pasNexKey command.
class PassNextKeyMode extends Mode {
  constructor(count) {
    if (count == null)
      count = 1;
    super();
    let seenKeyDown = false;
    let keyDownCount = 0;

    super.init({
      name: "pass-next-key",
      indicator: "Pass next key.",
      // We exit on blur because, once we lose the focus, we can no longer track key events.
      exitOnBlur: window,
      keypress: () => {
        return this.passEventToPage;
      },

      keydown: () => {
        seenKeyDown = true;
        keyDownCount += 1;
        return this.passEventToPage;
      },

      keyup: () => {
        if (seenKeyDown) {
          if (!(--keyDownCount > 0)) {
            if (!(--count > 0)) {
              this.exit();
            }
          }
        }
        return this.passEventToPage;
      }
    });
  }
}

global.InsertMode = InsertMode;
global.PassNextKeyMode = PassNextKeyMode;
