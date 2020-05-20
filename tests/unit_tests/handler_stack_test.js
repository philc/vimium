require("./test_helper.js");
require("../../lib/handler_stack.js");

context("handlerStack",
  setup(() => {
    stub(global, "DomUtils", {});
    stub(DomUtils, "consumeKeyup", () => {});
    stub(DomUtils, "suppressEvent", () => {});
    stub(DomUtils, "suppressPropagation", () => {});
    this.handlerStack = new HandlerStack;
    this.handler1Called = false;
    this.handler2Called = false;
  }),

  should("bubble events", () => {
    this.handlerStack.push({ keydown: () => { return this.handler1Called = true; } });
    this.handlerStack.push({ keydown: () => { return this.handler2Called = true; } });
    this.handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(this.handler2Called);
    assert.isTrue(this.handler1Called);
  }),

  should("terminate bubbling on falsy return value", () => {
    this.handlerStack.push({ keydown: () => { return this.handler1Called = true; } });
    this.handlerStack.push({
      keydown: () => {
      this.handler2Called = true;
      return false;
      }
    });
    this.handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(this.handler2Called);
    assert.isFalse(this.handler1Called);
  }),

  should("terminate bubbling on passEventToPage, and be true", () => {
    this.handlerStack.push({ keydown: () => { return this.handler1Called = true; } });
    this.handlerStack.push({
      keydown: () => {
        this.handler2Called = true;
        return this.handlerStack.passEventToPage;
      }
    });
    assert.isTrue(this.handlerStack.bubbleEvent('keydown', {}));
    assert.isTrue(this.handler2Called);
    assert.isFalse(this.handler1Called);
  }),

  should("terminate bubbling on passEventToPage, and be false", () => {
    this.handlerStack.push({ keydown: () => { return this.handler1Called = true; } });
    this.handlerStack.push({
      keydown: () => {
        this.handler2Called = true;
        return this.handlerStack.suppressPropagation;
      }
    });
    assert.isFalse(this.handlerStack.bubbleEvent('keydown', {}));
    assert.isTrue(this.handler2Called);
    assert.isFalse(this.handler1Called);
  }),

  should("restart bubbling on restartBubbling", () => {
    this.handler1Called = 0;
    this.handler2Called = 0;
    var id = this.handlerStack.push({
      keydown: () => {
        this.handler1Called++;
        this.handlerStack.remove(id);
        return this.handlerStack.restartBubbling;
      }
    });
    this.handlerStack.push({
      keydown: () => {
        this.handler2Called++;
        return true;
      }
    });
    assert.isTrue(this.handlerStack.bubbleEvent('keydown', {}));
    assert.isTrue(this.handler1Called === 1);
    assert.isTrue(this.handler2Called === 2);
  }),

  should("remove handlers correctly", () => {
    this.handlerStack.push({ keydown: () => { this.handler1Called = true; } });
    const handlerId = this.handlerStack.push({ keydown: () => { this.handler2Called = true; } });
    this.handlerStack.remove(handlerId);
    this.handlerStack.bubbleEvent('keydown', {});
    assert.isFalse(this.handler2Called);
    assert.isTrue(this.handler1Called);
  }),

  should("remove handlers correctly", () => {
    const handlerId = this.handlerStack.push({ keydown: () => { this.handler1Called = true; } });
    this.handlerStack.push({ keydown: () => { this.handler2Called = true; } });
    this.handlerStack.remove(handlerId);
    this.handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(this.handler2Called);
    assert.isFalse(this.handler1Called);
  }),

  should("handle self-removing handlers correctly", () => {
    const ctx = this;
    this.handlerStack.push({ keydown: () => { this.handler1Called = true; } });
    this.handlerStack.push({ keydown() {
      ctx.handler2Called = true;
      this.remove();
      return true;
    }
    });
    this.handlerStack.bubbleEvent('keydown', {});
    assert.isTrue(this.handler2Called);
    assert.isTrue(this.handler1Called);
    assert.equal(this.handlerStack.stack.length, 1);
  })
);
