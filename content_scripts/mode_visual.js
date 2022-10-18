// Symbolic names for some common strings.
const forward = "forward"; const backward = "backward"; const character = "character"; const word = "word"; const line = "line";
const sentence = "sentence"; const paragraph = "paragraph"; const vimword = "vimword"; const lineboundary= "lineboundary";

// This implements various selection movements.
class Movement {
  constructor(alterMethod) {
    this.alterMethod = alterMethod;
    this.opposite = {forward: backward, backward: forward};
    this.selection = window.getSelection();
  }

  // Return the character following (to the right of) the focus, and leave the selection unchanged, or return
  // undefined.
  getNextForwardCharacter() {
    const beforeText = this.selection.toString();
    if ((beforeText.length === 0) || (this.getDirection() === forward)) {
      this.selection.modify("extend", forward, character);
      const afterText = this.selection.toString();
      if (beforeText !== afterText) {
        this.selection.modify("extend", backward, character);
        return afterText[afterText.length - 1];
      }
    } else {
      return beforeText[0]; // The existing range selection is backwards.
    }
  }

  // Test whether the character following the focus is a word character (and leave the selection unchanged).
  nextCharacterIsWordCharacter() {
    // This regexp matches "word" characters.
    // From http://stackoverflow.com/questions/150033/regular-expression-to-match-non-english-characters.
    if (!this.regexp) {
      this.regexp = /[_0-9\u0041-\u005A\u0061-\u007A\u00AA\u00B5\u00BA\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u0527\u0531-\u0556\u0559\u0561-\u0587\u05D0-\u05EA\u05F0-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u08A0\u08A2-\u08AC\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0977\u0979-\u097F\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C33\u0C35-\u0C39\u0C3D\u0C58\u0C59\u0C60\u0C61\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D05-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D60\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E87\u0E88\u0E8A\u0E8D\u0E94-\u0E97\u0E99-\u0E9F\u0EA1-\u0EA3\u0EA5\u0EA7\u0EAA\u0EAB\u0EAD-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F4\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u1700-\u170C\u170E-\u1711\u1720-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1877\u1880-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191C\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19C1-\u19C7\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4B\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1CE9-\u1CEC\u1CEE-\u1CF1\u1CF5\u1CF6\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2183\u2184\u2C00-\u2C2E\u2C30-\u2C5E\u2C60-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005\u3006\u3031-\u3035\u303B\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312D\u3131-\u318E\u31A0-\u31BA\u31F0-\u31FF\u3400-\u4DB5\u4E00-\u9FCC\uA000-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA697\uA6A0-\uA6E5\uA717-\uA71F\uA722-\uA788\uA78B-\uA78E\uA790-\uA793\uA7A0-\uA7AA\uA7F8-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA80-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uABC0-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC]/;
    }
    return this.regexp.test(this.getNextForwardCharacter())
  }

  // Run a movement.  This is the core movement method, all movements happen here.  For convenience, the
  // following three argument forms are supported:
  //   runMovement("forward word")
  //   runMovement(["forward", "word"])
  //   runMovement("forward", "word")
  //
  // The granularities are word, "character", "line", "lineboundary", "sentence" and "paragraph".  In addition,
  // we implement the pseudo granularity "vimword", which implements vim-like word movement (e.g. "w").
  //
  runMovement(...args) {
    // Normalize the various argument forms.
    const [direction, granularity] =
          (typeof(args[0]) === "string") && (args.length === 1) ?
          args[0].trim().split(/\s+/) :
          (args.length === 1 ? args[0] : args.slice(0, 2));

    // Native word movements behave differently on Linux and Windows, see #1441.  So we implement some of them
    // character-by-character.
    if ((granularity === vimword) && (direction === forward)) {
      while (this.nextCharacterIsWordCharacter())
        if (this.extendByOneCharacter(forward) === 0)
          return;
      while (this.getNextForwardCharacter() && !this.nextCharacterIsWordCharacter())
        if (this.extendByOneCharacter(forward) === 0)
          return;
    } else if (granularity === vimword) {
      this.selection.modify(this.alterMethod, backward, word);
    }

    // As above, we implement this character-by-character to get consistent behavior on Windows and Linux.
    if ((granularity === word) && (direction === forward)) {
      while (this.getNextForwardCharacter() && !this.nextCharacterIsWordCharacter())
        if (this.extendByOneCharacter(forward) === 0)
          return;
      while (this.nextCharacterIsWordCharacter())
        if (this.extendByOneCharacter(forward) === 0)
          return;
    } else {
      return this.selection.modify(this.alterMethod, direction, granularity);
    }
  }

  // Swap the anchor node/offset and the focus node/offset.  This allows us to work with both ends of the
  // selection, and implements "o" for visual mode.
  reverseSelection() {
    const direction = this.getDirection();
    const element = document.activeElement;
    if (element && DomUtils.isEditable(element) && !element.isContentEditable) {
      // Note(smblott). This implementation is expensive if the selection is large.  We only use it here
      // because the normal method (below) does not work within text areas, etc.
      const length = this.selection.toString().length;
      this.collapseSelectionToFocus();
      for (let i = 0, end = length; i < end; i++)
        this.runMovement(this.opposite[direction], character);
    } else {
      // Normal method.
      const original = this.selection.getRangeAt(0).cloneRange();
      const range = original.cloneRange();
      range.collapse(direction === backward);
      this.setSelectionRange(range);
      const which = direction === forward ? "start" : "end";
      this.selection.extend(original[`${which}Container`], original[`${which}Offset`]);
    }
  }

  // Try to extend the selection by one character in direction.  Return positive, negative or 0, indicating
  // whether the selection got bigger, or smaller, or is unchanged.
  extendByOneCharacter(direction) {
    const length = this.selection.toString().length;
    this.selection.modify("extend", direction, character);
    return this.selection.toString().length - length;
  }

  // Get the direction of the selection.  The selection is "forward" if the focus is at or after the anchor,
  // and "backward" otherwise.
  // NOTE(smblott). This could be better, see: https://dom.spec.whatwg.org/#interface-range (however, that
  // probably wouldn't work for inputs).
  getDirection() {
    // Try to move the selection forward or backward, check whether it got bigger or smaller (then restore it).
    for (let direction of [ forward, backward ]) {
      var change;
      if (change = this.extendByOneCharacter(direction)) {
        this.extendByOneCharacter(this.opposite[direction]);
        if (change > 0)
          return direction;
        else
          return this.opposite[direction];
      }
    }
    return forward;
  }

  collapseSelectionToAnchor() {
    if (this.selection.toString().length > 0)
      return this.selection[this.getDirection() === backward ? "collapseToEnd" : "collapseToStart"]();
  }

  collapseSelectionToFocus() {
    if (this.selection.toString().length > 0)
      return this.selection[this.getDirection() === forward ? "collapseToEnd" : "collapseToStart"]();
  }

  setSelectionRange(range) {
    this.selection.removeAllRanges();
    // TODO(philc): Is this return needed?
    return this.selection.addRange(range);
  }

  // For "aw", "as".  We don't do "ap" (for paragraphs), because Chrome paragraph movements are weird.
  selectLexicalEntity(entity, count) {
    if (count == null)
      count = 1;
    this.collapseSelectionToFocus();
    // This makes word movements a bit more vim-like.
    if (entity === word)
      this.runMovement([ forward, character ]);
    this.runMovement([ backward, entity ]);
    this.collapseSelectionToFocus();
    for (let i = 0, end = count; i < end; i++)
      this.runMovement([ forward, entity ]);
  }

  selectLine(count) {
    // Even under caret mode, we still need an extended selection here.
    this.alterMethod = "extend";
    if (this.getDirection() === forward) { this.reverseSelection(); }
    this.runMovement(backward, lineboundary);
    this.reverseSelection();
    for (let i = 1, end = count; i < end; i++) { this.runMovement(forward, line); }
    this.runMovement(forward, lineboundary);
    // Include the next character if that character is a newline.
    if (this.getNextForwardCharacter() === "\n") { return this.runMovement(forward, character); }
  }

  // Scroll the focus into view.
  scrollIntoView() {
    if (DomUtils.getSelectionType(this.selection) !== "None") {
      const elementWithFocus = DomUtils.getElementWithFocus(this.selection, this.getDirection() === backward);
      if (elementWithFocus) { return Scroller.scrollIntoView(elementWithFocus); }
    }
  }
}

class VisualMode extends KeyHandlerMode {
  init(options) {
    let movement;
    if (options == null)
      options = {};
    this.movement = new Movement(options.alterMethod != null ? options.alterMethod : "extend");
    this.selection = this.movement.selection;

    // Build the key mapping structure required by KeyHandlerMode.  This only handles one- and two-key
    // mappings.
    const keyMapping = {};
    for (let keys of Object.keys(this.movements || {})) {
      movement = this.movements[keys];
      if ("function" === typeof movement)
        movement = movement.bind(this);
      if (keys.length === 1) {
        keyMapping[keys] = {command: movement};
      } else { // keys.length == 2
        if (keyMapping[keys[0]] == null)
          keyMapping[keys[0]] = {};
        Object.assign(keyMapping[keys[0]], {[keys[1]]: {command: movement}});
      }
    }

    // Aliases and complex bindings.
    Object.assign(keyMapping, {
      "B": keyMapping.b,
      "W": keyMapping.w,
      "<c-e>": {
        command(count) {
          return Scroller.scrollBy("y", count * Settings.get("scrollStepSize"), 1, false);
        }
      },
      "<c-y>": {
        command(count) {
          return Scroller.scrollBy("y", -count * Settings.get("scrollStepSize"), 1, false);
        }
      }
    });

    super.init(Object.assign(options, {
      name: options.name != null ? options.name : "visual",
      indicator: options.indicator != null ? options.indicator : "Visual mode",
      singleton: "visual-mode-group", // Visual mode, visual-line mode and caret mode each displace each other.
      exitOnEscape: true,
      suppressAllKeyboardEvents: true,
      keyMapping,
      commandHandler: this.commandHandler.bind(this)
    }));

    // If there was a range selection when the user lanuched visual mode, then we retain the selection on exit.
    this.shouldRetainSelectionOnExit = this.options.userLaunchedMode
      && (DomUtils.getSelectionType(this.selection) === "Range");

    this.onExit((event = null) => {
      // Retain any selection, regardless of how we exit.
      if (this.shouldRetainSelectionOnExit) {
        null;
        // This mimics vim: when leaving visual mode via Escape, collapse to focus, otherwise collapse to anchor.
      } else if (event && (event.type === "keydown") && KeyboardUtils.isEscape(event) && (this.name !== "caret")) {
        this.movement.collapseSelectionToFocus();
      } else {
        this.movement.collapseSelectionToAnchor();
      }

      // Don't leave the user in insert mode just because they happen to have selected an input.
      if (document.activeElement && DomUtils.isEditable(document.activeElement))
        if ((event != null ? event.type : undefined) !== "click")
          return document.activeElement.blur();
    });

    this.push({
      _name: `${this.id}/enter/click`,
      // Yank on <Enter>.
      keypress: event => {
        if (event.key === "Enter") {
          if (!event.metaKey && !event.ctrlKey && !event.altKey && !event.shiftKey) {
            this.yank();
            return this.suppressEvent;
          }
        }
        return this.continueBubbling;
      },
      // Click in a focusable element exits.
      click: event => this.alwaysContinueBubbling(() => {
        if (DomUtils.isFocusable(event.target))
          return this.exit(event);
      })
    });

    // Establish or use the initial selection.  If that's not possible, then enter caret mode.
    if (this.name !== "caret") {
      if (["Caret", "Range"].includes(DomUtils.getSelectionType(this.selection))) {
        let selectionRect = this.selection.getRangeAt(0).getBoundingClientRect();
        if (window.vimiumDomTestsAreRunning) {
          // We're running the DOM tests, where getBoundingClientRect() isn't available.
          if (!selectionRect)
            selectionRect = {top: 0, bottom: 0, left: 0, right: 0, width: 0, height: 0};
        }
        selectionRect = Rect.intersect(selectionRect, Rect.create(0, 0, window.innerWidth, window.innerHeight));
        if ((selectionRect.height >= 0) && (selectionRect.width >= 0)) {
          // The selection is visible in the current viewport.
          if (DomUtils.getSelectionType(this.selection) === "Caret")
            // The caret is in the viewport. Make make it visible.
            this.movement.extendByOneCharacter(forward) || this.movement.extendByOneCharacter(backward);
        } else {
          // The selection is outside of the viewport: clear it.  We guess that the user has moved on, and is
          // more likely to be interested in visible content.
          this.selection.removeAllRanges();
        }
      }

      if ((DomUtils.getSelectionType(this.selection) !== "Range") && (this.name !== "caret")) {
        new CaretMode().init();
        return HUD.showForDuration("No usable selection, entering caret mode...", 2500);
      }
    }
  }

  commandHandler({command: {command}, count}) {
    switch (typeof command) {
    case "string":
      for (let i = 0, end = count; i < end; i++)
        this.movement.runMovement(command);
      break;
    case "function":
      command(count);
      break;
    }
    return this.movement.scrollIntoView();
  }

  // find: (count, backwards) =>
  find(count, backwards) {
    const initialRange = this.selection.getRangeAt(0).cloneRange();
    for (let i = 0, end = count; i < end; i++) {
      const nextQuery = FindMode.getQuery(backwards);
      if (!nextQuery) {
        HUD.showForDuration("No query to find.", 1000);
        return;
      }
      if (!FindMode.execute(nextQuery, {colorSelection: false, backwards})) {
        this.movement.setSelectionRange(initialRange);
        HUD.showForDuration(`No matches for '${FindMode.query.rawQuery}'`, 1000);
        return;
      }
    }

    // The find was successfull. If we're in caret mode, then we should now have a selection, so we can
    // drop back into visual mode.
    if ((this.name === "caret") && (this.selection.toString().length > 0)) {
      const mode = new VisualMode();
      mode.init();
      return mode;
    }
  }

  // Yank the selection; always exits; collapses the selection; set @yankedText and return it.
  yank(args) {
    if (args == null)
      args = {};
    this.yankedText = this.selection.toString();
    this.exit();
    HUD.copyToClipboard(this.yankedText);

    let message = this.yankedText.replace(/\s+/g, " ");
    if (15 < this.yankedText.length)
      message = message.slice(0, 12) + "...";
    const plural = this.yankedText.length === 1 ? "" : "s";
    HUD.showForDuration(`Yanked ${this.yankedText.length} character${plural}: \"${message}\".`, 2500);

    return this.yankedText;
  }
}

  // A movement can be either a string or a function.
VisualMode.prototype.movements = {
  "l": "forward character",
  "h": "backward character",
  "j": "forward line",
  "k": "backward line",
  "e": "forward word",
  "b": "backward word",
  "w": "forward vimword",
  ")": "forward sentence",
  "(": "backward sentence",
  "}": "forward paragraph",
  "{": "backward paragraph",
  "0": "backward lineboundary",
  "$": "forward lineboundary",
  "G": "forward documentboundary",
  "gg": "backward documentboundary",

  "aw"(count) { return this.movement.selectLexicalEntity(word, count); },
  "as"(count) { return this.movement.selectLexicalEntity(sentence, count); },

  "n"(count) { return this.find(count, false); },
  "N"(count) { return this.find(count, true); },
  "/"() {
    this.exit();
    return new FindMode({returnToViewport: true}).onExit(() => new VisualMode().init());
  },

  "y"() { return this.yank(); },
  "Y"(count) { this.movement.selectLine(count); return this.yank(); },
  "p"() { return chrome.runtime.sendMessage({handler: "openUrlInCurrentTab", url: this.yank()}); },
  "P"() { return chrome.runtime.sendMessage({handler: "openUrlInNewTab", url: this.yank()}); },
  "v"() { return new VisualMode().init(); },
  "V"() { return new VisualLineMode().init(); },
  "c"() {
    // If we're already in caret mode, or if the selection looks the same as it would in caret mode, then
    // callapse to anchor (so that the caret-mode selection will seem unchanged).  Otherwise, we're in visual
    // mode and the user has moved the focus, so collapse to that.
    if ((this.name === "caret") || (this.selection.toString().length <= 1))
      this.movement.collapseSelectionToAnchor();
    else
      this.movement.collapseSelectionToFocus();
    return new CaretMode().init();
  },
  "o"() { return this.movement.reverseSelection(); }
};

class VisualLineMode extends VisualMode {
  init(options) {
    if (options == null)
      options = {};
    super.init(Object.assign(options, {name: "visual/line", indicator: "Visual mode (line)"}));
    return this.extendSelection();
  }

  commandHandler({command: {command}, count}) {
    switch (typeof command) {
      case "string":
        for (let i = 0, end = count; i < end; i++) {
          this.movement.runMovement(command);
          // If the current selection
          //  * has only 1 line (the line that is selected when we # enter the visual line mode), and
          //  * its direction is different from the command,
          // then the command will in effect unselect that line. In this case, we restore that line and
          // reverse its direction, keeping that line selected.
          if (this.selection.isCollapsed) {
            this.extendSelection();
            const [direction, granularity] = command.split(' ');
            if ((this.movement.getDirection() !== direction) && (granularity === "line"))
              this.movement.reverseSelection();
            this.movement.runMovement(command);
          }
        }
        break;
      case "function":
        command(count);
        break;
    }
    this.movement.scrollIntoView();
    if (this.modeIsActive)
      return this.extendSelection();
  }

  extendSelection() {
    const initialDirection = this.movement.getDirection();
    // TODO(philc): Reformat this to be a plain loop rather than a closure.
    return (() => {
      const result = [];
      for (let direction of [ initialDirection, this.movement.opposite[initialDirection] ]) {
        this.movement.runMovement(direction, lineboundary);
        result.push(this.movement.reverseSelection());
      }
      return result;
    })();
  }
}

class CaretMode extends VisualMode {
  init(options) {
    if (options == null)
      options = {};
    super.init(Object.assign(options, {name: "caret", indicator: "Caret mode", alterMethod: "move"}));

    // Establish the initial caret.
    switch (DomUtils.getSelectionType(this.selection)) {
      case "None":
        this.establishInitialSelectionAnchor();
        if (DomUtils.getSelectionType(this.selection) === "None") {
          this.exit();
          HUD.showForDuration("Create a selection before entering visual mode.", 2500);
          return;
        }
        break;
      case "Range":
        this.movement.collapseSelectionToAnchor();
        break;
    }

    this.movement.extendByOneCharacter(forward);
    return this.movement.scrollIntoView();
  }

  commandHandler(...args) {
    this.movement.collapseSelectionToAnchor();
    super.commandHandler(...(args || []));
    if (this.modeIsActive)
      return this.movement.extendByOneCharacter(forward);
  }

  // When visual mode starts and there's no existing selection, we launch CaretMode and try to establish a
  // selection. As a heuristic, we pick the first non-whitespace character of the first visible text node
  // which seems to be big enough to be interesting.
  // TODO(smblott). It might be better to do something similar to Clearly or Readability; that is, try to find
  // the start of the page's main textual content.
  establishInitialSelectionAnchor() {
    let node;
    const nodes = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    while ((node = nodes.nextNode())) {
      // Don't choose short text nodes; they're likely to be part of a banner.
      if ((node.nodeType === 3) && (50 <= node.data.trim().length)) {
        const element = node.parentElement;
        if (DomUtils.getVisibleClientRect(element) && !DomUtils.isEditable(element)) {
          // Start at the offset of the first non-whitespace character.
          const offset = node.data.length - node.data.replace(/^\s+/, "").length;
          const range = document.createRange();
          range.setStart(node, offset);
          range.setEnd(node, offset);
          this.movement.setSelectionRange(range);
          return true;
        }
      }
    }
    return false;
  }
}

window.VisualMode = VisualMode;
window.VisualLineMode = VisualLineMode;
