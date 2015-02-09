root = exports ? window

class HandlerStack
  constructor: ->
    @debug = false
    @eventNumber = 0
    @stack = []
    @counter = 0

    # A handler should return this value to immediately discontinue bubbling and pass the event on to the
    # underlying page.
    @stopBubblingAndTrue = new Object()

    # A handler should return this value to indicate that the event has been consumed, and no further
    # processing should take place.  The event does not propagate to the underlying page.
    @stopBubblingAndFalse = new Object()

    # A handler should return this value to indicate that bubbling should be restarted.  Typically, this is
    # used when, while bubbling an event, a new mode is pushed onto the stack.
    @restartBubbling = new Object()

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
  # event's propagation by returning a falsy value, or stop bubbling by returning @stopBubblingAndFalse or
  # @stopBubblingAndTrue.
  bubbleEvent: (type, event) ->
    @eventNumber += 1
    eventNumber = @eventNumber
    # We take a copy of the array in order to avoid interference from concurrent removes (for example, to
    # avoid calling the same handler twice, because elements have been spliced out of the array by remove).
    for handler in @stack[..].reverse()
      # A handler may have been removed (handler.id == null), so check.
      if handler?.id and handler[type]
        @currentId = handler.id
        result = handler[type].call @, event
        @logResult eventNumber, type, event, handler, result if @debug
        if not result
          DomUtils.suppressEvent event  if @isChromeEvent event
          return false
        return true if result == @stopBubblingAndTrue
        return false if result == @stopBubblingAndFalse
        return @bubbleEvent type, event if result == @restartBubbling
      else
        @logResult eventNumber, type, event, handler, "skip" if @debug
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
  alwaysContinueBubbling: (handler) ->
    handler()
    true

  neverContinueBubbling: (handler) ->
    handler()
    false

  # Debugging.
  logResult: (eventNumber, type, event, handler, result) ->
    # FIXME(smblott).  Badge updating is too noisy, so we filter it out.  However, we do need to look at how
    # many badge update events are happening.  It seems to be more than necessary. We also filter out
    # registerKeyQueue as unnecessarily noisy and not particularly helpful.
    return if type in [ "updateBadge", "registerKeyQueue" ]
    label =
      switch result
        when @stopBubblingAndTrue then "stop/true"
        when @stopBubblingAndFalse then "stop/false"
        when @restartBubbling then "rebubble"
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
