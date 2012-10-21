root = exports ? window

class root.HandlerStack

  constructor: ->
    @stack = []
    @counter = 0

  genId: -> @counter = ++@counter & 0xffff

  # Adds a handler to the stack. Returns a unique ID for that handler that can be used to remove it later.
  push: (handler) ->
    handler.id = @genId()
    @stack.push handler
    handler.id

  # Called whenever we receive a key event. Each individual handler has the option to stop the event's
  # propagation by returning a falsy value.
  bubbleEvent: (type, event) ->
    for i in [(@stack.length - 1)..0] by -1
      handler = @stack[i]
      # We need to check for existence of handler because the last function call may have caused the release
      # of more than one handler.
      if handler && handler[type]
        @currentId = handler.id
        passThrough = handler[type].call(@, event)
        if not passThrough
          DomUtils.suppressEvent(event)
          return false
    true

  remove: (id = @currentId) ->
    for i in [(@stack.length - 1)..0] by -1
      handler = @stack[i]
      if handler.id == id
        @stack.splice(i, 1)
        break
