markHookSet = "vimium-hooked-delegated-onclick-listeners"
return if document.documentElement.hasAttribute(markHookSet)


Object.defineProperty window, "jQuery",
  enumerable: yes
  configurable: yes
  set: (jQuery) ->
    _on = jQuery.fn.on

    jQuery.fn.on = (evnt, selector, handlerFn) ->
      if evnt is "click" and typeof selector is "string"
        attrKey = "vimium-jquery-delegated-events-selectors"
        sep = "|"

        element = if @[0] is document then document.documentElement else @[0]
        selectors = element.getAttribute(attrKey) || sep
        if selectors.indexOf("#{sep}#{selector}#{sep}") < 0
          element.setAttribute attrKey, selectors + selector + sep

      return _on.apply @, arguments

    return jQuery


document.documentElement.setAttribute markHookSet, ""
