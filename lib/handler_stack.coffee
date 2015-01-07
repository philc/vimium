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
  # We use unshift (which is more expensive than push) so that bubbleEvent can just iterate over the stack in
  # the normal order.
  push: (handler) ->
    @stack.unshift handler
    handler.id = ++@counter

  # Called whenever we receive a key or other event. Each individual handler has the option to stop the
  # event's propagation by returning a falsy value, or stop bubbling by returning @stopBubblingAndFalse or
  # @stopBubblingAndTrue.
  bubbleEvent: (type, event) ->
    # extra is passed to each handler.  This allows handlers to pass information down the stack.
    extra = {}
    for handler in @stack[..] # Take a copy of @stack, so that concurrent removes do not interfere.
      # We need to check whether the handler has been removed (handler.id == null).
      if handler and handler.id
        @currentId = handler.id
        # A handler can register a handler for type "all", which will be invoked on all events.  Such an "all"
        # handler will be invoked first.
        for func in [ handler.all, handler[type] ]
          if func
            passThrough = func.call @, event, extra
            if not passThrough
              DomUtils.suppressEvent(event) if @isChromeEvent event
              return false
            return true if passThrough == @stopBubblingAndTrue
            return false if passThrough == @stopBubblingAndFalse
    true

  remove: (id = @currentId) ->
    # This is more expense than splicing @stack, but better because splicing can interfere with concurrent
    # bubbleEvents.
    @stack = @stack.filter (handler) ->
      # Mark this handler as removed (so concurrent bubbleEvents will know not to invoke it).
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
