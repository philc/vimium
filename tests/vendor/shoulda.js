/*
 * A unit testing micro framework. Tests are grouped into "contexts", each of which can share common
 * setup and teardown functions.
 */

/*
 * Assertions.
 */
const assert = {
  isTrue(value) {
    if (!value) {
      this.fail("Expected true, but got " + value);
    }
  },

  isFalse(value) {
    if (value) {
      this.fail("Expected false, but got " + value);
    }
  },

  // Does a deep-equal check on complex objects.
  equal(expected, actual) {
    const areEqual = typeof expected === "object"
      ? JSON.stringify(expected) === JSON.stringify(actual)
      : expected === actual;
    if (!areEqual) {
      this.fail(`Expected:\n${this._print(expected)}\nGot:\n${this._print(actual)}`);
    }
  },

  // We cannot name this function simply "throws", because it's a reserved JavaScript keyword.
  throwsError(expression, errorName) {
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

  fail(message) {
    throw new AssertionError(message);
  },

  // Used for printing the arguments passed to assertions.
  _print(object) {
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
    return fn?.apply(null, arguments);
  };
  Tests.requiredCallbacks.push(wrappedFunction);
  return wrappedFunction;
}

class AssertionError extends Error {
  constructor(message) {
    super(message);
    this.name = "AssertionError";
    // Omit this constructor from the error's backtrace.
    Error.captureStackTrace?.(this, AssertionError);
  }
}

/*
 * A Context is a named set of test methods and nested contexts, with optional setup and teardown
 * methods.
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

  // The list of callbacks created by `ensureCalled` which must be called by the end of the test.
  requiredCallbacks: [],

  // True if, during the collection phase, should.only or context.only was used.
  focusIsUsed: false,

  /*
   * Run all contexts which have been defined.
   * - testNameFilter: a String. If provided, only run tests which match testNameFilter will be run.
   */
  async run(testNameFilter) {
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
  reset() {
    this.topLevelContexts = [];
    this.focusedTests = [];
    this.focusIsUsed = false;
  },

  /*
   * Run a context. This runs the test methods defined in the context first, and then any nested
   * contexts.
   */
  async runContext(context, parentContexts, testNameFilter) {
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
   * Run a test. This will run all setup methods in all contexts, and then all teardown methods.
   * - testMethod: an object with keys name, fn.
   * - contexts: an array of Contexts, ordered outer to inner.
   * - testNameFilter: A String. If provided, only run the test if it matches testNameFilter.
   */
  async runTest(testMethod, contexts, testNameFilter) {
    const shouldSkip = this.focusIsUsed && !testMethod.isFocused &&
      !contexts.some((c) => c.isFocused);
    if (shouldSkip) return;

    const fullTestName = this.fullyQualifiedName(testMethod.name, contexts);
    if (testNameFilter && !fullTestName.includes(testNameFilter)) {
      return;
    }

    this.testsRun++;
    let failureMessage = null;
    // This is the scope which all references to "this" in the setup and test methods resolve to.
    const testScope = {};

    const errors = [];

    for (const context of contexts.filter((c) => c.setupMethod)) {
      try {
        await context.setupMethod.call(testScope, testScope);
      } catch (error) {
        errors.push(error);
        break;
      }
    }

    if (errors.length == 0) {
      try {
        await testMethod.fn.call(testScope, testScope);
      } catch (error) {
        errors.push(error);
      }
    }

    for (const context of contexts.filter((c) => c.teardownMethod)) {
      try {
        await context.teardownMethod.call(testScope, testScope);
      } catch (error) {
        errors.push(error);
        break;
      }
    }

    if (this.requiredCallbacks.length > 0) {
      errors.push("A callback function should have been called during this test, but wasn't.");
    }

    if (errors.length > 0) {
      Tests.testsFailed++;
    }

    // Print the errors in the order they occurred in the setup, test, teardown chain.
    for (const [i, error] of Object.entries(errors)) {
      // Note that in JavaScript, any object can be thrown, even a string or null.
      let message;
      if (Error.isError(error)) {
        if (error instanceof AssertionError) {
          message = error.message;
        } else {
          // In Deno and Chrome, error.stack also includes the error's message.
          message = error.stack;
        }
      } else {
        // Thrown types which are not Errors will not have a backtrace.
        message = String(error);
      }

      // For the first failure only, print the failed test header message.
      if (i == 0) {
        Tests.printFailure(fullTestName, message);
      } else {
        console.log("---"); // Add a visual separator between backtraces when there are many.
        console.log(message);
      }
    }

    this.requiredCallbacks = [];
    clearStubs();
  },

  // The fully-qualified name of the test or context, e.g. "context1: context2: testName".
  fullyQualifiedName(testName, contexts) {
    return contexts.map((c) => c.name).concat(testName).join(": ");
  },

  printTestSummary() {
    if (this.testsFailed > 0) {
      console.log(`Fail (${Tests.testsFailed}/${Tests.testsRun})`);
    } else {
      console.log(`Pass (${Tests.testsRun}/${Tests.testsRun})`);
    }
  },

  printFailure(testName, failureMessage) {
    console.log(`Fail "${testName}"\n${failureMessage}`);
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
