markHookSet = "vimium-hooked-delegated-onclick-listeners"
return if document.documentElement.hasAttribute(markHookSet)

_jQuery = undefined

Object.defineProperty window, "jQuery",
  enumerable: yes
  configurable: yes
  get: -> _jQuery
  set: (jQuery) ->
    _jQuery = jQuery
    _on = jQuery.fn.on

    jQuery.fn.on = (evnt, selector, handlerFn) ->
      element = if @[0] in [document, window] then document.documentElement else @[0]

      hadOnClickListener = (element?.hasAttribute? "vimium-has-onclick-listener") ? yes
      result = _on.apply @, arguments

      # Early return when no element exist, as there is nothing we can mark.
      return result unless element

      if evnt is "click" and typeof selector is "string"
        attrKey = "vimium-jquery-delegated-events-selectors"
        sep = "|"

        selectors = element.getAttribute(attrKey) || sep
        if selectors.indexOf("#{sep}#{selector}#{sep}") < 0
          element.setAttribute attrKey, selectors + selector + sep

      # jQuery uses a single call of `addEventListener` to listen for normal and delegated events.
      # We don't want to show a link hint for element, that works ONLY as a container for such listeners.
      # However, we do want to show a link hint, if element has listener for its own, normal events.
      if evnt is "click"
        if typeof selector is "string"
          # If there was no listener before, currently listener captures only delegated events.
          # No need to show link hint in this case.
          element.removeAttribute "vimium-has-onclick-listener" unless hadOnClickListener
        else
          # If there was a listener for delegated events before, `addEventListener` will not be called again.
          # Make sure we show link hint.
          element.setAttribute "vimium-has-onclick-listener", ""

      return result

    return jQuery


document.documentElement.setAttribute markHookSet, ""
