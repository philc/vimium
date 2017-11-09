root = exports ? (window.root ?= {})

class HandlerStack
  constructor: ->
    @debug = false
    @eventNumber = 0
    @stack = []
    @counter = 0

    # A handler should return this value to immediately discontinue bubbling and pass the event on to the
    # underlying page.
    @passEventToPage = new Object()

    # A handler should return this value to indicate that the event has been consumed, and no further
    # processing should take place.  The event does not propagate to the underlying page.
    @suppressPropagation = new Object()

    # A handler should return this value to indicate that bubbling should be restarted.  Typically, this is
    # used when, while bubbling an event, a new mode is pushed onto the stack.
    @restartBubbling = new Object()

    # A handler should return this value to continue bubbling the event.
    @continueBubbling = true

    # A handler should return this value to suppress an event.
    @suppressEvent = false

  # Adds a handler to the top of the stack. Returns a unique ID for that handler that can be used to remove it
  # later.
  push: (handler) ->
    handler._name ||= "anon-#{@counter}"
    @stack.push handler
    handler.id = ++@counter

  # As above, except the new handler is added to the bottom of the stack.
  unshift: (handler) ->
    handler._name ||= "anon-#{@counter}"
    handler._name += "/unshift"
    @stack.unshift handler
    handler.id = ++@counter

  # Called whenever we receive a key or other event. Each individual handler has the option to stop the
  # event's propagation by returning a falsy value, or stop bubbling by returning @suppressPropagation or
  # @passEventToPage.
  bubbleEvent: (type, event) ->
    @eventNumber += 1
    eventNumber = @eventNumber
    for handler in @stack[..].reverse()
      # A handler might have been removed (handler.id == null), so check; or there might just be no handler
      # for this type of event.
      unless handler?.id and handler[type]
        @logResult eventNumber, type, event, handler, "skip [#{handler[type]?}]" if @debug
      else
        @currentId = handler.id
        result = handler[type].call this, event
        @logResult eventNumber, type, event, handler, result if @debug
        if result == @passEventToPage
          return true
        else if result == @suppressPropagation
          if type == "keydown"
            DomUtils.consumeKeyup event, null, true
          else
            DomUtils.suppressPropagation event
          return false
        else if result == @restartBubbling
          return @bubbleEvent type, event
        else if result == @continueBubbling or (result and result != @suppressEvent)
          true # Do nothing, but continue bubbling.
        else
          # result is @suppressEvent or falsy.
          if @isChromeEvent event
            if type == "keydown"
              DomUtils.consumeKeyup event
            else
              DomUtils.suppressEvent event
          return false

    # None of our handlers care about this event, so pass it to the page.
    true

  remove: (id = @currentId) ->
    for i in [(@stack.length - 1)..0] by -1
      handler = @stack[i]
      if handler.id == id
        # Mark the handler as removed.
        handler.id = null
        @stack.splice(i, 1)
        break

  # The handler stack handles chrome events (which may need to be suppressed) and internal (pseudo) events.
  # This checks whether the event at hand is a chrome event.
  isChromeEvent: (event) ->
    event?.preventDefault? or event?.stopImmediatePropagation?

  # Convenience wrappers.  Handlers must return an approriate value.  These are wrappers which handlers can
  # use to always return the same value.  This then means that the handler itself can be implemented without
  # regard to its return value.
  alwaysContinueBubbling: (handler = null) ->
    handler?()
    @continueBubbling

  alwaysSuppressPropagation: (handler = null) ->
    if handler?() == @suppressEvent then @suppressEvent else @suppressPropagation

  # Debugging.
  logResult: (eventNumber, type, event, handler, result) ->
    if event?.type == "keydown" # Tweak this as needed.
      label =
        switch result
          when @passEventToPage then "passEventToPage"
          when @suppressEvent then "suppressEvent"
          when @suppressPropagation then "suppressPropagation"
          when @restartBubbling then "restartBubbling"
          when "skip" then "skip"
          when true then "continue"
      label ||= if result then "continue/truthy" else "suppress"
      console.log "#{eventNumber}", type, handler._name, label

  show: ->
    console.log "#{@eventNumber}:"
    for handler in @stack[..].reverse()
      console.log "  ", handler._name

  # For tests only.
  reset: ->
    @stack = []

root.HandlerStack = HandlerStack
root.handlerStack = new HandlerStack()
extend window, root unless exports?
