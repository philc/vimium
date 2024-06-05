/*
 * A unit testing micro framework. Tests are grouped into "contexts", each of which can share common
 * setup functions.
 */

/*
 * Assertions.
 */
const assert = {
  isTrue: function (value) {
    if (!value) {
      this.fail("Expected true, but got " + value);
    }
  },

  isFalse: function (value) {
    if (value) {
      this.fail("Expected false, but got " + value);
    }
  },

  // Does a deep-equal check on complex objects.
  equal: function (expected, actual) {
    const areEqual = typeof expected === "object"
      ? JSON.stringify(expected) === JSON.stringify(actual)
      : expected === actual;
    if (!areEqual) {
      this.fail(
        `\nExpected:\n${this._print(expected)}\nGot:\n${this._print(actual)}\n`,
      );
    }
  },

  // We cannot name this function simply "throws", because it's a reserved JavaScript keyword.
  throwsError: function (expression, errorName) {
    try {
      expression();
    } catch (error) {
      if (errorName) {
        if (error.name == errorName) {
          return;
        } else {
          assert.fail(
            `Expected error ${errorName} to be thrown but error ${error.name} was thrown instead.`,
          );
        }
      } else {
        return;
      }
    }
    if (errorName) {
      assert.fail(`Expected error ${errorName} but no error was thrown.`);
    } else {
      assert.fail("Expected error but none was thrown.");
    }
  },

  fail: function (message) {
    throw new AssertionError(message);
  },

  // Used for printing the arguments passed to assertions.
  _print: function (object) {
    if (object === null) return "null";
    else if (object === undefined) return "undefined";
    else if (typeof object === "string") return '"' + object + '"';
    else {
      try {
        // Pretty-print with indentation.
        return JSON.stringify(object, undefined, 2);
      } catch (_) {
        // `object` might not be stringifiable (e.g. DOM nodes), or JSON.stringify may not exist.
        return object.toString();
      }
    }
  },
};

/*
 * ensureCalled ensures the given function is called by the end of the test case. This is useful
 * when testing APIs that use callbacks.
 */
function ensureCalled(fn) {
  const wrappedFunction = function () {
    const i = Tests.requiredCallbacks.indexOf(wrappedFunction);
    if (i >= 0) {
      Tests.requiredCallbacks.splice(i, 1); // Delete.
    }
    return fn.apply(null, arguments);
  };
  Tests.requiredCallbacks.push(wrappedFunction);
  return wrappedFunction;
}

function AssertionError(message) {
  this.name = AssertionError;
  this.message = message;
}
AssertionError.prototype = new Error();
AssertionError.prototype.constructor = AssertionError;

/*
 * A Context is a named set of test methods and nested contexts, with optional setup and teardown
 * blocks.
 */
function Context(name) {
  this.name = name;
  this.setupMethod = null;
  this.teardownMethod = null;
  this.contexts = [];
  this.tests = [];
}

const contextStack = [];

/*
 * See the usage documentation for details on how to use the "context" and "should" functions.
 */
function context(name, fn) {
  if (typeof fn != "function") {
    throw new Error("context() requires a function argument.");
  }
  const newContext = new Context(name);
  if (contextStack.length > 0) {
    contextStack[contextStack.length - 1].tests.push(newContext);
  } else {
    Tests.topLevelContexts.push(newContext);
  }
  contextStack.push(newContext);
  fn();
  contextStack.pop();
  return newContext;
}

context.only = (name, fn) => {
  const c = context(name, fn);
  c.isFocused = true;
  Tests.focusIsUsed = true;
};

function setup(fn) {
  contextStack[contextStack.length - 1].setupMethod = fn;
}

function teardown(fn) {
  contextStack[contextStack.length - 1].teardownMethod = fn;
}

function should(name, fn) {
  const test = { name, fn };
  contextStack[contextStack.length - 1].tests.push(test);
  return test;
}

should.only = (name, fn) => {
  const test = should(name, fn);
  test.isFocused = true;
  Tests.focusIsUsed = true;
};

/*
 * Tests is used to run tests and keep track of the count of successes and failures.
 */
const Tests = {
  topLevelContexts: [],
  testsRun: 0,
  testsFailed: 0,

  // The list of callbacks to ensure are called by the end of the test. This list is appended to by
  // `ensureCalled`.
  requiredCallbacks: [],

  // True if, during the collection phase, should.only or context.only was used.
  focusIsUsed: false,

  /*
   * Run all contexts which have been defined.
   * - testNameFilter: a String. If provided, only run tests which match testNameFilter will be run.
   */
  run: async function (testNameFilter) {
    // Run every top level context (i.e. those not defined within another context). These will in
    // turn run any nested contexts. The very last context ever added to Tests.testContexts is a top
    // level context. Note that any contexts which have not already been run by a previous top level
    // context must themselves be top level contexts.
    this.testsRun = 0;
    this.testsFailed = 0;
    for (const context of this.topLevelContexts) {
      await this.runContext(context, [], testNameFilter);
    }
    this.printTestSummary();
    return this.testsFailed == 0;
  },

  /*
   * This resets (clears) the state of shoulda, including the tests which have been defined. This is
   * useful when running shoulda tests in a REPL environment, to prevent tests from getting defined
   * multiple times when a file is re-evaluated.
   */
  reset: function () {
    this.topLevelContexts = [];
    this.focusedTests = [];
    this.focusIsUsed = false;
  },

  /*
   * Run a context. This runs the test methods defined in the context first, and then any nested
   * contexts.
   */
  runContext: async function (context, parentContexts, testNameFilter) {
    parentContexts = parentContexts.concat([context]);
    for (const test of context.tests) {
      if (test instanceof Context) {
        await this.runContext(test, parentContexts, testNameFilter);
      } else {
        await this.runTest(test, parentContexts, testNameFilter);
      }
    }
  },

  /*
   * Run a test method. This will run all setup methods in all contexts, and then all teardown
   * methods.
   * - testMethod: an object with keys name, fn.
   * - contexts: an array of Contexts, ordered outer to inner.
   * - testNameFilter: A String. If provided, only run the test if it matches testNameFilter.
   */
  runTest: async function (testMethod, contexts, testNameFilter) {
    if (
      this.focusIsUsed && !testMethod.isFocused &&
      !contexts.some((c) => c.isFocused)
    ) {
      return;
    }
    const fullTestName = this.fullyQualifiedName(testMethod.name, contexts);
    if (testNameFilter && !fullTestName.includes(testNameFilter)) {
      return;
    }

    this.testsRun++;
    let failureMessage = null;
    // This is the scope which all references to "this" in the setup and test methods will resolve to.
    const testScope = {};

    try {
      try {
        for (const context of contexts) {
          if (context.setupMethod) {
            await context.setupMethod.call(testScope, testScope);
          }
        }
        await testMethod.fn.call(testScope, testScope);
      } finally {
        for (const context of contexts) {
          if (context.teardownMethod) {
            await context.teardownMethod.call(testScope, testScope);
          }
        }
      }
    } catch (error) {
      // Note that error can be either a String or an Error.
      const failedAssertion = error instanceof AssertionError;
      failureMessage = failedAssertion ? error.message : error.toString();
      if (!failedAssertion && error.stack) {
        failureMessage += "\n" + error.stack;
      }
    }

    if (!failureMessage && this.requiredCallbacks.length > 0) {
      failureMessage =
        "A callback function should have been called during this test, but it wasn't.";
    }
    if (failureMessage) {
      Tests.testsFailed++;
      Tests.printFailure(fullTestName, failureMessage);
    }

    this.requiredCallbacks = [];
    clearStubs();
  },

  // The fully-qualified name of the test or context, e.g. "context1: context2: testName".
  fullyQualifiedName: function (testName, contexts) {
    return contexts.map((c) => c.name).concat(testName).join(": ");
  },

  printTestSummary: function () {
    if (this.testsFailed > 0) {
      console.log(`Fail (${Tests.testsFailed}/${Tests.testsRun})`);
    } else {
      console.log(`Pass (${Tests.testsRun}/${Tests.testsRun})`);
    }
  },

  printFailure: function (testName, failureMessage) {
    console.log(`Fail "${testName}"`, failureMessage);
  },
};

function run(testNameFilter) {
  return Tests.run(testNameFilter);
}

function reset() {
  Tests.reset();
}

/*
 * Stats of the latest test run.
 */
function getStats() {
  return {
    failed: Tests.testsFailed,
    run: Tests.testsRun,
  };
}

/*
 * Stubs
 */
const stubbedObjects = [];

function stub(object, propertyName, returnValue) {
  stubbedObjects.push({
    object: object,
    propertyName: propertyName,
    original: object[propertyName],
  });
  object[propertyName] = returnValue;
}

/*
 * returns creates a function which returns the given value. This is useful for stubbing functions
 * to return a hardcoded value.
 */
function returns(value) {
  return () => value;
}

function clearStubs() {
  // Restore stubs in the reverse order they were defined in, in case the same property was stubbed
  // twice.
  for (let i = stubbedObjects.length - 1; i >= 0; i--) {
    const stubProperties = stubbedObjects[i];
    stubProperties.object[stubProperties.propertyName] = stubProperties.original;
  }
}

export {
  assert,
  context,
  ensureCalled,
  getStats,
  reset,
  returns,
  run,
  setup,
  should,
  stub,
  teardown,
};
