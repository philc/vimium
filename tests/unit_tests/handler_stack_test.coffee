require "./test_helper.js"
extend(global, require "../../lib/handler_stack.js")

context "handlerStack",
  setup ->
    stub global, "DomUtils", {}
    stub DomUtils, "consumeKeyup", ->
    stub DomUtils, "suppressEvent", ->
    stub DomUtils, "suppressPropagation", ->
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

  should "terminate bubbling on passEventToPage, and be true", ->
    @handlerStack.push { keydown: => @handler1Called = true }
    @handlerStack.push { keydown: => @handler2Called = true; @handlerStack.passEventToPage }
    assert.isTrue @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler2Called
    assert.isFalse @handler1Called

  should "terminate bubbling on passEventToPage, and be false", ->
    @handlerStack.push { keydown: => @handler1Called = true }
    @handlerStack.push { keydown: => @handler2Called = true; @handlerStack.suppressPropagation }
    assert.isFalse @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler2Called
    assert.isFalse @handler1Called

  should "restart bubbling on restartBubbling", ->
    @handler1Called = 0
    @handler2Called = 0
    id = @handlerStack.push { keydown: => @handler1Called++; @handlerStack.remove(id); @handlerStack.restartBubbling }
    @handlerStack.push { keydown: => @handler2Called++; true  }
    assert.isTrue @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler1Called == 1
    assert.isTrue @handler2Called == 2

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
    ctx = this
    @handlerStack.push { keydown: => @handler1Called = true }
    @handlerStack.push { keydown: ->
      ctx.handler2Called = true
      @remove()
    }
    @handlerStack.bubbleEvent 'keydown', {}
    assert.isTrue @handler2Called
    assert.isTrue @handler1Called
    assert.equal @handlerStack.stack.length, 1
