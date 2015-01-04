root = exports ? window

class HandlerStack

  constructor: ->
    @stack = []
    @counter = 0

    # A handler should return this value to immediately discontinue bubbling and pass the event on to the
    # underlying page.
    @stopBubblingAndTrue = new Object()

    # A handler should return this value to indicate that the event has been consumed, and no further
    # processing should take place.
    @stopBubblingAndFalse = new Object()

  # Adds a handler to the stack. Returns a unique ID for that handler that can be used to remove it later.
  push: (handler) ->
    @stack.push handler
    handler.id = ++@counter

  # Called whenever we receive a key or other event. Each individual handler has the option to stop the
  # event's propagation by returning a falsy value, or stop bubbling by returning @stopBubblingAndFalse or
  # @stopBubblingAndTrue.
  bubbleEvent: (type, event) ->
    # extra is passed to each handler.  This allows handlers to pass information down the stack.
    extra = {}
    for i in [(@stack.length - 1)..0] by -1
      handler = @stack[i]
      # We need to check for existence of handler because the last function call may have caused the release
      # of more than one handler.
      if handler and handler.id and handler[type]
        @currentId = handler.id
        passThrough = handler[type].call @, event, extra
        if not passThrough
          DomUtils.suppressEvent(event) if @isChromeEvent event
          return false
        return true if passThrough == @stopBubblingAndTrue
        return false if passThrough == @stopBubblingAndFalse
    true

  remove: (id = @currentId) ->
    if 0 < @stack.length and @stack[@stack.length-1].id == id
      # A common case is to remove the handler at the top of the stack.  And we can this very efficiently.
      # Tests suggest that this case arises more than half of the time.
      @stack.pop().id = null
    else
      # Otherwise, we'll build a new stack.  This is better than splicing the existing stack since at can't
      # interfere with any concurrent bubbleEvent.
      @stack = @stack.filter (handler) ->
        # Mark this handler as removed (for any active bubbleEvent call).
        handler.id = null if handler.id == id
        handler?.id?

  # The handler stack handles chrome events (which may need to be suppressed) and internal (fake) events.
  # This checks whether that the event at hand is a chrome event.
  isChromeEvent: (event) ->
    event?.preventDefault? and event?.stopImmediatePropagation?

  # Convenience wrappers.
  alwaysContinueBubbling: (handler) ->
    handler()
    true

  neverContinueBubbling: (handler) ->
    handler()
    false

root.HandlerStack = HandlerStack
root.handlerStack = new HandlerStack
