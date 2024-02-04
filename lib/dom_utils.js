const DomUtils = {
  //
  // Runs :callback if the DOM has loaded, otherwise runs it on load
  //
  isReady() {
    return document.readyState !== "loading";
  },

  documentReady: (function () {
    // TODO(philc): Why isn't isReady a const? Why does it need to be set to true
    // upon the DOMContentLoaded event?
    let isReady = document.readyState !== "loading";

    let callbacks = [];
    if (!isReady) {
      let onDOMContentLoaded;
      globalThis.addEventListener(
        "DOMContentLoaded",
        onDOMContentLoaded = forTrusted(function () {
          globalThis.removeEventListener("DOMContentLoaded", onDOMContentLoaded, true);
          isReady = true;
          for (const callback of callbacks) callback();
          callbacks = null;
        }),
        true,
      );
    }

    return function (callback) {
      if (isReady) {
        return callback();
      } else {
        callbacks.push(callback);
      }
    };
  })(),

  documentComplete: (function () {
    let isComplete = document.readyState === "complete";
    let callbacks = [];
    if (!isComplete) {
      let onLoad;
      globalThis.addEventListener(
        "load",
        onLoad = forTrusted(function (event) {
          // The target is ensured to be on document. See
          // https://w3c.github.io/uievents/#event-type-load
          if (event.target !== document) return;
          globalThis.removeEventListener("load", onLoad, true);
          isComplete = true;
          for (const callback of callbacks) callback();
          callbacks = null;
        }),
        true,
      );
    }

    return function (callback) {
      if (isComplete) {
        callback();
      } else {
        callbacks.push(callback);
      }
    };
  })(),

  createElement(tagName) {
    const element = document.createElement(tagName);
    if (element instanceof HTMLElement) {
      // The document namespace provides (X)HTML elements, so we can use them directly.
      this.createElement = (tagName) => document.createElement(tagName);
      return element;
    } else {
      // The document namespace doesn't give (X)HTML elements, so we create them with the correct
      // namespace manually.
      this.createElement = (tagName) =>
        document.createElementNS("http://www.w3.org/1999/xhtml", tagName);
      return this.createElement(tagName);
    }
  },

  //
  // Adds a list of elements to a new container div, and adds that to the page.
  // Returns the container div.
  //
  // Note that adding these nodes all at once (via a parent div) is significantly faster than
  // one-by-one.
  addElementsToPage(elements, containerOptions) {
    const parent = this.createElement("div");
    if (containerOptions.id != null) parent.id = containerOptions.id;
    if (containerOptions.className != null) parent.className = containerOptions.className;
    for (const el of elements) parent.appendChild(el);
    document.documentElement.appendChild(parent);
    return parent;
  },

  //
  // Remove an element from its DOM tree.
  //
  removeElement(el) {
    return el.parentNode.removeChild(el);
  },

  //
  // Test whether the current frame is the top/main frame.
  //
  isTopFrame() {
    return globalThis.top === globalThis.self;
  },

  //
  // Takes an array of XPath selectors, adds the necessary namespaces (currently only XHTML), and
  // applies them to the document root. The namespaceResolver in evaluateXPath should be kept in
  // sync with the namespaces here.
  //
  makeXPath(elementArray) {
    const xpath = [];
    for (const element of elementArray) {
      xpath.push(".//" + element, ".//xhtml:" + element);
    }
    return xpath.join(" | ");
  },

  // Evaluates an XPath on the whole document, or on the contents of the fullscreen element if an
  // element is fullscreen.
  evaluateXPath(xpath, resultType) {
    const contextNode = document.webkitIsFullScreen
      ? document.webkitFullscreenElement
      : document.documentElement;
    const namespaceResolver = function (namespace) {
      if (namespace === "xhtml") return "http://www.w3.org/1999/xhtml";
      else return null;
    };
    return document.evaluate(xpath, contextNode, namespaceResolver, resultType, null);
  },

  //
  // Returns the first visible clientRect of an element if it exists. Otherwise it returns null.
  //
  // WARNING: If testChildren = true then the rects of visible (eg. floated) children may be
  // returned instead. This is used for LinkHints and focusInput, **BUT IS UNSUITABLE FOR MOST OTHER
  // PURPOSES**.
  //
  getVisibleClientRect(element, testChildren) {
    // Note: this call will be expensive if we modify the DOM in between calls.
    let clientRect;
    if (testChildren == null) testChildren = false;
    const clientRects = (() => {
      const result = [];
      for (clientRect of element.getClientRects()) {
        result.push(Rect.copy(clientRect));
      }
      return result;
    })();

    // Inline elements with font-size: 0px; will declare a height of zero, even if a child with
    // non-zero font-size contains text.
    let isInlineZeroHeight = function () {
      const elementComputedStyle = window.getComputedStyle(element, null);
      const isInlineZeroFontSize =
        (0 === elementComputedStyle.getPropertyValue("display").indexOf("inline")) &&
        (elementComputedStyle.getPropertyValue("font-size") === "0px");
      // Override the function to return this value for the rest of this context.
      isInlineZeroHeight = () => isInlineZeroFontSize;
      return isInlineZeroFontSize;
    };

    for (clientRect of clientRects) {
      // If the link has zero dimensions, it may be wrapping visible but floated elements. Check for
      // this.
      let computedStyle;
      if (((clientRect.width === 0) || (clientRect.height === 0)) && testChildren) {
        for (const child of Array.from(element.children)) {
          computedStyle = window.getComputedStyle(child, null);
          // Ignore child elements which are not floated and not absolutely positioned for parent
          // elements with zero width/height, as long as the case described at isInlineZeroHeight
          // does not apply.
          // NOTE(mrmr1993): This ignores floated/absolutely positioned descendants nested within
          // inline children.
          const position = computedStyle.getPropertyValue("position");
          if (
            (computedStyle.getPropertyValue("float") === "none") &&
            !(["absolute", "fixed"].includes(position)) &&
            !((clientRect.height === 0) && isInlineZeroHeight() &&
              (0 === computedStyle.getPropertyValue("display").indexOf("inline")))
          ) {
            continue;
          }
          const childClientRect = this.getVisibleClientRect(child, true);
          if (
            (childClientRect === null) || (childClientRect.width < 3) ||
            (childClientRect.height < 3)
          ) continue;
          return childClientRect;
        }
      } else {
        clientRect = this.cropRectToVisible(clientRect);

        if ((clientRect === null) || (clientRect.width < 3) || (clientRect.height < 3)) continue;

        // eliminate invisible elements (see test_harnesses/visibility_test.html)
        computedStyle = window.getComputedStyle(element, null);
        if (computedStyle.getPropertyValue("visibility") !== "visible") continue;

        return clientRect;
      }
    }

    return null;
  },

  //
  // Bounds the rect by the current viewport dimensions. If the rect is offscreen or has a height or
  // width < 3 then null is returned instead of a rect.
  //
  cropRectToVisible(rect) {
    const boundedRect = Rect.create(
      Math.max(rect.left, 0),
      Math.max(rect.top, 0),
      rect.right,
      rect.bottom,
    );
    if (
      (boundedRect.top >= (window.innerHeight - 4)) || (boundedRect.left >= (window.innerWidth - 4))
    ) {
      return null;
    } else {
      return boundedRect;
    }
  },

  //
  // Get the client rects for the <area> elements in a <map> based on the position of the <img>
  // element using the map. Returns an array of rects.
  //
  getClientRectsForAreas(imgClientRect, areaEls) {
    const rects = [];
    for (const areaEl of areaEls) {
      let x1, x2, y1, y2;
      const coords = areaEl.coords.split(",").map((coord) => parseInt(coord, 10));
      const shape = areaEl.shape.toLowerCase();
      if (["rect", "rectangle"].includes(shape)) { // "rectangle" is an IE non-standard.
        if (coords.length == 4) {
          [x1, y1, x2, y2] = coords;
        }
      } else if (["circle", "circ"].includes(shape)) { // "circ" is an IE non-standard.
        if (coords.length == 3) {
          const [x, y, r] = coords;
          const diff = r / Math.sqrt(2); // Gives us an inner square
          x1 = x - diff;
          x2 = x + diff;
          y1 = y - diff;
          y2 = y + diff;
        }
      } else if (shape === "default") {
        if (coords.length == 2) {
          [x1, y1, x2, y2] = [0, 0, imgClientRect.width, imgClientRect.height];
        }
      } else {
        if (coords.length >= 4) {
          // Just consider the rectangle surrounding the first two points in a polygon. It's possible
          // to do something more sophisticated, but likely not worth the effort.
          [x1, y1, x2, y2] = coords;
        }
      }

      let rect = Rect.translate(Rect.create(x1, y1, x2, y2), imgClientRect.left, imgClientRect.top);
      rect = this.cropRectToVisible(rect);

      // The wrong numbere of coords in a <map> element, or malformed numbers, can result in NaN
      // values.
      const isValid = rect && !isNaN(rect.top) && !isNaN(rect.left) && !isNaN(rect.width) &&
        !isNaN(rect.height);
      if (isValid) rects.push({ element: areaEl, rect });
    }
    return rects;
  },

  //
  // Selectable means that we should use the simulateSelect method to activate the element instead
  // of a click.
  //
  // The html5 input types that should use simulateSelect are:
  //   ["date", "datetime", "datetime-local", "email", "month", "number", "password", "range",
  //    "search", "tel", "text", "time", "url", "week"]
  // An unknown type will be treated the same as "text", in the same way that the browser does.
  //
  isSelectable(element) {
    if (!(element instanceof Element)) return false;
    const unselectableTypes = [
      "button",
      "checkbox",
      "color",
      "file",
      "hidden",
      "image",
      "radio",
      "reset",
      "submit",
    ];
    return ((element.nodeName.toLowerCase() === "input") &&
      (unselectableTypes.indexOf(element.type) === -1)) ||
      (element.nodeName.toLowerCase() === "textarea") || element.isContentEditable;
  },

  // Input or text elements are considered focusable and able to receieve their own keyboard events,
  // and will enter insert mode if focused. Also note that the "contentEditable" attribute can be
  // set on any element which makes it a rich text editor, like the notes on jjot.com.
  isEditable(element) {
    return (this.isSelectable(element)) ||
      ((element.nodeName != null ? element.nodeName.toLowerCase() : undefined) === "select");
  },

  // Embedded elements like Flash and quicktime players can obtain focus.
  isEmbed(element) {
    const nodeName = element.nodeName != null ? element.nodeName.toLowerCase() : null;
    return ["embed", "object"].includes(nodeName);
  },

  isFocusable(element) {
    return element && (this.isEditable(element) || this.isEmbed(element));
  },

  isDOMDescendant(parent, child) {
    let node = child;
    while (node !== null) {
      if (node === parent) return true;
      node = node.parentNode;
    }
    return false;
  },

  // True if element is editable and contains the active selection range.
  isSelected(element) {
    const selection = document.getSelection();
    if (element.isContentEditable) {
      const node = selection.anchorNode;
      return node && this.isDOMDescendant(element, node);
    } else {
      if ((DomUtils.getSelectionType(selection) === "Range") && selection.isCollapsed) {
        // The selection is inside the Shadow DOM of a node. We can check the node it registers as
        // being before, since this represents the node whose Shadow DOM it's inside.
        const containerNode = selection.anchorNode.childNodes[selection.anchorOffset];
        return element === containerNode; // True if the selection is inside the Shadow DOM of our element.
      } else {
        return false;
      }
    }
  },

  simulateSelect(element) {
    // If element is already active, then we don't move the selection. However, we also won't get a
    // new focus event. So, instead we pretend (to any active modes which care, e.g. PostFindMode)
    // that element has been clicked.
    if ((element === document.activeElement) && DomUtils.isEditable(document.activeElement)) {
      return handlerStack.bubbleEvent("click", { target: element });
    } else {
      element.focus();
      if ((element.tagName.toLowerCase() !== "textarea") || (element.value.indexOf("\n") < 0)) {
        // If the cursor is at the start of the (non-multiline-textarea) element's contents, send it
        // to the end.
        // Motivation:
        // * the end is a more useful place to focus than the start,
        // * this way preserves the last used position (except when it's at the beginning), so the
        //   user can 'resume where they left off'.
        // This works well for single-line inputs, however, the UX is *bad* for multiline inputs
        // (such as text areas), and doubly so if the end of the input happens to be out of the
        // viewport, that's why multiline-textareas are excluded.
        // NOTE(mrmr1993): Some elements throw an error when we try to access their selection
        // properties, so wrap this with a try.
        try {
          if ((element.selectionStart === 0) && (element.selectionEnd === 0)) {
            return element.setSelectionRange(element.value.length, element.value.length);
          }
        } catch {
          // Swallow
        }
      }
    }
  },

  simulateClick(element, modifiers) {
    if (modifiers == null) modifiers = {};
    const eventSequence = [
      "pointerover",
      "mouseover",
      "pointerdown",
      "mousedown",
      "pointerup",
      "mouseup",
      "click",
    ];
    for (const event of eventSequence) {
      this.simulateMouseEvent(event, element, modifiers);
    }
  },

  // Returns false if the event is cancellable and one of the handlers called
  // event.preventDefault().
  simulateMouseEvent(event, element, modifiers) {
    if (modifiers == null) modifiers = {};
    if (event === "mouseout") {
      // Allow unhovering the last hovered element by passing undefined.
      if (element == null) element = this.lastHoveredElement;
      this.lastHoveredElement = undefined;
      if (element == null) return;
    } else if (event === "mouseover") {
      // Simulate moving the mouse off the previous element first, as if we were a real mouse.
      this.simulateMouseEvent("mouseout", undefined, modifiers);
      this.lastHoveredElement = element;
    }

    const mouseEvent = new MouseEvent(event, {
      bubbles: true,
      cancelable: true,
      composed: true,
      view: window,
      detail: 1,
      ctrlKey: modifiers.ctrlKey,
      altKey: modifiers.altKey,
      shiftKey: modifiers.shiftKey,
      metaKey: modifiers.metaKey,
    });
    return element.dispatchEvent(mouseEvent);
  },

  simulateClickDefaultAction(element, modifiers) {
    let newTabModifier;
    if (modifiers == null) modifiers = {};
    if (
      ((element.tagName != null ? element.tagName.toLowerCase() : undefined) !== "a") ||
      !element.href
    ) return;

    const { ctrlKey, shiftKey, metaKey, altKey } = modifiers;

    // Mac uses a different new tab modifier (meta vs. ctrl).
    if (KeyboardUtils.platform === "Mac") {
      newTabModifier = (metaKey === true) && (ctrlKey === false);
    } else {
      newTabModifier = (metaKey === false) && (ctrlKey === true);
    }

    if (newTabModifier) {
      // Open in new tab. Shift determines whether the tab is focused when created. Alt is ignored.
      chrome.runtime.sendMessage({
        handler: "openUrlInNewTab",
        url: element.href,
        active: shiftKey === true,
      });
    } else if (
      (shiftKey === true) && (metaKey === false) && (ctrlKey === false) && (altKey === false)
    ) {
      // Open in new window.
      chrome.runtime.sendMessage({ handler: "openUrlInNewWindow", url: element.href });
    } else if (element.target === "_blank") {
      chrome.runtime.sendMessage({ handler: "openUrlInNewTab", url: element.href, active: true });
    }
  },

  simulateHover(element, modifiers) {
    if (modifiers == null) modifiers = {};
    return this.simulateMouseEvent("mouseover", element, modifiers);
  },

  simulateUnhover(element, modifiers) {
    if (modifiers == null) modifiers = {};
    return this.simulateMouseEvent("mouseout", element, modifiers);
  },

  addFlashRect(rect) {
    const flashEl = this.createElement("div");
    flashEl.classList.add("vimiumReset");
    flashEl.classList.add("vimiumFlash");
    flashEl.style.left = rect.left + "px";
    flashEl.style.top = rect.top + "px";
    flashEl.style.width = rect.width + "px";
    flashEl.style.height = rect.height + "px";
    document.documentElement.appendChild(flashEl);
    return flashEl;
  },

  getViewportTopLeft() {
    const box = document.documentElement;
    const style = getComputedStyle(box);
    const rect = box.getBoundingClientRect();
    if ((style.position === "static") && !/content|paint|strict/.test(style.contain || "")) {
      // The margin is included in the client rect, so we need to subtract it back out.
      const marginTop = parseInt(style.marginTop);
      const marginLeft = parseInt(style.marginLeft);
      return { top: -rect.top + marginTop, left: -rect.left + marginLeft };
    } else {
      let clientLeft, clientTop;
      if (Utils.isFirefox()) {
        // These are always 0 for documentElement on Firefox, so we derive them from CSS border.
        clientTop = parseInt(style.borderTopWidth);
        clientLeft = parseInt(style.borderLeftWidth);
      } else {
        ({ clientTop, clientLeft } = box);
      }
      return { top: -rect.top - clientTop, left: -rect.left - clientLeft };
    }
  },

  suppressPropagation(event) {
    event.stopImmediatePropagation();
  },

  suppressEvent(event) {
    event.preventDefault();
    this.suppressPropagation(event);
  },

  consumeKeyup: (function () {
    let handlerId = null;

    return function (event, callback = null, suppressPropagation) {
      if (!event.repeat) {
        if (handlerId != null) handlerStack.remove(handlerId);
        const {
          code,
        } = event;
        handlerId = handlerStack.push({
          _name: "dom_utils/consumeKeyup",
          keyup(event) {
            if (event.code !== code) return handlerStack.continueBubbling;
            this.remove();
            if (suppressPropagation) {
              DomUtils.suppressPropagation(event);
            } else {
              DomUtils.suppressEvent(event);
            }
            return handlerStack.continueBubbling;
          },
          // We cannot track keyup events if we lose the focus.
          blur(event) {
            if (event.target === window) this.remove();
            return handlerStack.continueBubbling;
          },
        });
      }
      if (typeof callback === "function") {
        callback();
      }
      if (suppressPropagation) {
        DomUtils.suppressPropagation(event);
        return handlerStack.suppressPropagation;
      } else {
        DomUtils.suppressEvent(event);
        return handlerStack.suppressEvent;
      }
    };
  })(),

  // Polyfill for selection.type (which is not available in Firefox).
  getSelectionType(selection) {
    if (selection == null) selection = document.getSelection();
    if (selection.type) {
      return selection.type;
    } else if (selection.rangeCount === 0) {
      return "None";
    } else if (selection.isCollapsed) {
      return "Caret";
    } else {
      return "Range";
    }
  },

  // Adapted from: http://roysharon.com/blog/37.
  // This finds the element containing the selection focus.
  getElementWithFocus(selection, backwards) {
    let t;
    let r = (t = selection.getRangeAt(0));
    if (DomUtils.getSelectionType(selection) === "Range") {
      r = t.cloneRange();
      r.collapse(backwards);
    }
    t = r.startContainer;
    if (t.nodeType === 1) t = t.childNodes[r.startOffset];
    let o = t;
    while (o && (o.nodeType !== 1)) o = o.previousSibling;
    t = o || (t != null ? t.parentNode : undefined);
    return t;
  },

  getSelectionFocusElement() {
    const sel = window.getSelection();
    let node = sel.focusNode;
    if ((node == null)) {
      return null;
    }
    if ((node === sel.anchorNode) && (sel.focusOffset === sel.anchorOffset)) {
      // If the selection is not a caret inside a `#text`, which has no child nodes, then it either
      // *is* an element, or is inside an opaque element (eg. <input>).
      node = node.childNodes[sel.focusOffset] || node;
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return node.parentElement;
    else return node;
  },

  // Get the element in the DOM hierachy that contains `element`.
  // If the element is rendered in a shadow DOM via a <content> element, the <content> element will
  // be returned, so the shadow DOM is traversed rather than passed over.
  getContainingElement(element) {
    return (typeof element.getDestinationInsertionPoints === "function"
      ? element.getDestinationInsertionPoints()[0]
      : undefined) || element.parentElement;
  },

  // This tests whether a window is too small to be useful.
  windowIsTooSmall() {
    return (window.innerWidth < 3) || (window.innerHeight < 3);
  },

  // Inject user styles manually. This is only necessary for our chrome-extension:// pages and
  // frames.
  injectUserCss() {
    const style = document.createElement("style");
    style.type = "text/css";
    style.textContent = Settings.get("userDefinedLinkHintCss");
    document.head.appendChild(style);
  },
};

window.DomUtils = DomUtils;
