const Marks = {
  previousPositionRegisters: ["`", "'"],
  localRegisters: {},
  currentRegistryEntry: null,
  mode: null,

  exit(continuation = null) {
    if (this.mode != null) {
      this.mode.exit();
    }
    this.mode = null;
    if (continuation) {
      return continuation(); // TODO(philc): Is this return necessary?
    }
  },

  // This returns the key which is used for storing mark locations in localStorage.
  getLocationKey(keyChar) {
    return `vimiumMark|${window.location.href.split("#")[0]}|${keyChar}`;
  },

  getMarkString() {
    return JSON.stringify({
      scrollX: window.scrollX,
      scrollY: window.scrollY,
      hash: window.location.hash,
    });
  },

  setPreviousPosition() {
    const markString = this.getMarkString();
    for (const reg of this.previousPositionRegisters) {
      this.localRegisters[reg] = markString;
    }
  },

  showMessage(message, keyChar) {
    HUD.show(`${message} \"${keyChar}\".`, 1000);
  },

  // If <Shift> is depressed, then it's a global mark, otherwise it's a local mark. This is
  // consistent vim's [A-Z] for global marks and [a-z] for local marks. However, it also admits
  // other non-Latin characters. The exceptions are "`" and "'", which are always considered local
  // marks. The "swap" command option inverts global and local marks.
  isGlobalMark(event, keyChar) {
    let shiftKey = event.shiftKey;
    if (this.currentRegistryEntry.options.swap) {
      shiftKey = !shiftKey;
    }
    return shiftKey && !this.previousPositionRegisters.includes(keyChar);
  },

  activateCreateMode(_count, { registryEntry }) {
    this.currentRegistryEntry = registryEntry;
    this.mode = new Mode();
    this.mode.init({
      name: "create-mark",
      indicator: "Create mark...",
      exitOnEscape: true,
      suppressAllKeyboardEvents: true,
      keydown: (event) => {
        if (KeyboardUtils.isPrintable(event)) {
          const keyChar = KeyboardUtils.getKeyChar(event);
          this.exit(() => {
            if (this.isGlobalMark(event, keyChar)) {
              // We record the current scroll position, but only if this is the top frame within the
              // tab. Otherwise, we'll fetch the scroll position of the top frame from the
              // background page later.
              let scrollX, scrollY;
              if (DomUtils.isTopFrame()) {
                [scrollX, scrollY] = [window.scrollX, window.scrollY];
              }
              chrome.runtime.sendMessage({
                handler: "createMark",
                markName: keyChar,
                scrollX,
                scrollY,
              }, () => this.showMessage("Created global mark", keyChar));
            } else {
              localStorage[this.getLocationKey(keyChar)] = this.getMarkString();
              this.showMessage("Created local mark", keyChar);
            }
          });
          return handlerStack.suppressEvent;
        }
      },
    });
  },

  activateGotoMode(_count, { registryEntry }) {
    this.currentRegistryEntry = registryEntry;
    this.mode = new Mode();
    this.mode.init({
      name: "goto-mark",
      indicator: "Go to mark...",
      exitOnEscape: true,
      suppressAllKeyboardEvents: true,
      keydown: (event) => {
        if (KeyboardUtils.isPrintable(event)) {
          this.exit(() => {
            const keyChar = KeyboardUtils.getKeyChar(event);
            if (this.isGlobalMark(event, keyChar)) {
              // This key must match @getLocationKey() in the back end.
              const key = `vimiumGlobalMark|${keyChar}`;
              chrome.storage.local.get(key, function (items) {
                if (key in items) {
                  chrome.runtime.sendMessage({ handler: "gotoMark", markName: keyChar });
                  HUD.show(`Jumped to global mark '${keyChar}'`, 1000);
                } else {
                  HUD.show(`Global mark not set '${keyChar}'`, 1000);
                }
              });
            } else {
              const markString = this.localRegisters[keyChar] != null
                ? this.localRegisters[keyChar]
                : localStorage[this.getLocationKey(keyChar)];
              if (markString != null) {
                this.setPreviousPosition();
                const position = JSON.parse(markString);
                if (position.hash && (position.scrollX === 0) && (position.scrollY === 0)) {
                  window.location.hash = position.hash;
                } else {
                  window.scrollTo(position.scrollX, position.scrollY);
                }
                this.showMessage("Jumped to local mark", keyChar);
              } else {
                this.showMessage("Local mark not set", keyChar);
              }
            }
          });
          return handlerStack.suppressEvent;
        }
      },
    });
  },
};

window.Marks = Marks;
