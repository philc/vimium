import "./test_helper.js";
import "../../lib/handler_stack.js";

context("handlerStack", () => {
  let handlerStack, handler1Called, handler2Called;

  setup(() => {
    stub(window, "DomUtils", {});
    stub(DomUtils, "consumeKeyup", () => {});
    stub(DomUtils, "suppressEvent", () => {});
    stub(DomUtils, "suppressPropagation", () => {});
    handlerStack = new HandlerStack;
    handler1Called = false;
    handler2Called = false;
  });

  should("bubble events", () => {
    handlerStack.push({ keydown: () => { return handler1Called = true; } });
    handlerStack.push({ keydown: () => { return handler2Called = true; } });
    handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(handler2Called);
    assert.isTrue(handler1Called);
  });

  should("terminate bubbling on falsy return value", () => {
    handlerStack.push({ keydown: () => { return handler1Called = true; } });
    handlerStack.push({
      keydown: () => {
      handler2Called = true;
      return false;
      }
    });
    handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(handler2Called);
    assert.isFalse(handler1Called);
  });

  should("terminate bubbling on passEventToPage, and be true", () => {
    handlerStack.push({ keydown: () => { return handler1Called = true; } });
    handlerStack.push({
      keydown: () => {
        handler2Called = true;
        return handlerStack.passEventToPage;
      }
    });
    assert.isTrue(handlerStack.bubbleEvent('keydown', {}));
    assert.isTrue(handler2Called);
    assert.isFalse(handler1Called);
  });

  should("terminate bubbling on passEventToPage, and be false", () => {
    handlerStack.push({ keydown: () => { return handler1Called = true; } });
    handlerStack.push({
      keydown: () => {
        handler2Called = true;
        return handlerStack.suppressPropagation;
      }
    });
    assert.isFalse(handlerStack.bubbleEvent('keydown', {}));
    assert.isTrue(handler2Called);
    assert.isFalse(handler1Called);
  });

  should("restart bubbling on restartBubbling", () => {
    handler1Called = 0;
    handler2Called = 0;
    var id = handlerStack.push({
      keydown: () => {
        handler1Called++;
        handlerStack.remove(id);
        return handlerStack.restartBubbling;
      }
    });
    handlerStack.push({
      keydown: () => {
        handler2Called++;
        return true;
      }
    });
    assert.isTrue(handlerStack.bubbleEvent('keydown', {}));
    assert.isTrue(handler1Called === 1);
    assert.isTrue(handler2Called === 2);
  });

  should("remove handlers correctly", () => {
    handlerStack.push({ keydown: () => { handler1Called = true; } });
    const handlerId = handlerStack.push({ keydown: () => { handler2Called = true; } });
    handlerStack.remove(handlerId);
    handlerStack.bubbleEvent('keydown', {});
    assert.isFalse(handler2Called);
    assert.isTrue(handler1Called);
  });

  should("remove handlers correctly", () => {
    const handlerId = handlerStack.push({ keydown: () => { handler1Called = true; } });
    handlerStack.push({ keydown: () => { handler2Called = true; } });
    handlerStack.remove(handlerId);
    handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(handler2Called);
    assert.isFalse(handler1Called);
  });

  should("handle self-removing handlers correctly", () => {
    handlerStack.push({ keydown: () => { handler1Called = true; } });
    handlerStack.push({
      keydown() {
        handler2Called = true;
        this.remove();
        return true;
      }
    });
    handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(handler2Called);
    assert.isTrue(handler1Called);
    assert.equal(handlerStack.stack.length, 1);
  });
});
