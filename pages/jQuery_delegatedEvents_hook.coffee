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
    _off = jQuery.fn.off

    attrKey = "vimium-jquery-delegated-events-selectors"
    sep = "|"

    jQuery.fn.on = (evnt, selector, handlerFn) ->
      if evnt is "click" and typeof selector is "string"
        element = if @[0] is document then document.documentElement else @[0]
        selectors = element.getAttribute(attrKey) || sep
        if selectors.indexOf("#{sep}#{selector}#{sep}") < 0
          element.setAttribute attrKey, selectors + selector + sep

        # jQuery will use addEventListener, but we don't want to hook this particular call.
        skipCounter = parseInt element.getAttribute("vimium-skip-onclick-listener") || "0"
        element.setAttribute "vimium-skip-onclick-listener", skipCounter + 1

      return _on.apply @, arguments

    jQuery.fn.off = (evnt, selector) ->
      if evnt is "click" and typeof selector is "string"
        element = if @[0] is document then document.documentElement else @[0]
        selectors = element.getAttribute(attrKey) || sep
        boundedSelector = "#{sep}#{selector}#{sep}"

        if selector is "**" or selectors is boundedSelector
          element.removeAttribute attrKey
        else if selectors.indexOf(boundedSelector) > -1
          element.setAttribute attrKey, selectors.replace(boundedSelector, "")

      return _off.apply @, arguments

    return jQuery


document.documentElement.setAttribute markHookSet, ""
