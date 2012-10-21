require "./test_helper.js"
extend(global, require "../../lib/handler_stack.js")

context "handlerStack",
  setup ->
    stub global, "DomUtils", {}
    stub DomUtils, "suppressEvent", ->
    @handlerStack = new HandlerStack
    @handler1Called = false
    @handler2Called = false

  should "bubble events", ->
    @handlerStack.push { keydown: => @handler1Called = true }
    @handlerStack.push { keydown: => @handler2Called = true }
    @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler2Called
    assert.isTrue @handler1Called

  should "terminate bubbling on falsy return value", ->
    @handlerStack.push { keydown: => @handler1Called = true }
    @handlerStack.push { keydown: => @handler2Called = true; false }
    @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler2Called
    assert.isFalse @handler1Called

  should "remove handlers correctly", ->
    @handlerStack.push { keydown: => @handler1Called = true }
    handlerId = @handlerStack.push { keydown: => @handler2Called = true }
    @handlerStack.remove handlerId
    @handlerStack.bubbleEvent 'keydown', {}
    assert.isFalse @handler2Called
    assert.isTrue @handler1Called

  should "remove handlers correctly", ->
    handlerId = @handlerStack.push { keydown: => @handler1Called = true }
    @handlerStack.push { keydown: => @handler2Called = true }
    @handlerStack.remove handlerId
    @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler2Called
    assert.isFalse @handler1Called

  should "handle self-removing handlers correctly", ->
    ctx = @
    @handlerStack.push { keydown: => @handler1Called = true }
    @handlerStack.push { keydown: ->
      ctx.handler2Called = true
      @remove()
    }
    @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler2Called
    assert.isTrue @handler1Called
    assert.equal @handlerStack.stack.length, 1
