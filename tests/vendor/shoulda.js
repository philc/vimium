/*
 * A unit testing framework to group tests into "contexts", each of which can optionally share common setup
 * blocks. This framework also supports stubbing out properties and methods of objects. See
 * https://github.com/philc/shoulda.js
 *
 * Version: 1.0
 *
 * To write your tests, use this format:

   context("Chessboard",
     setup(function() { ... }),

     should("Initialize itself", function() { ... }),

     context("Chess piece",
       setup: function() { ... },
       should("Only allow valid moves", function() { ... })
     )
   );

 * To stub properties of an object:

   // Stub a method
   stub(document, "getElementById", function() { ... });
   stub(document, "getElementById", returns(myElement));

   // Stub a property
   stubs(window.location, "href", "http://myurl.com");

 * To run your tests after you've defined them using contexts:
   Tests.run()
 * Calling Tests.run() with a String argument will only run the subset of your tests which match the argument.
 */

scope = (typeof window === "undefined") ? global : window;

/*
 * Assertions.
 */
scope.assert = {
  isTrue: function(value) {
    if (!value)
      this.fail("Expected true, but was " + value);
  },

  isFalse: function(value) {
    if (value)
      this.fail("Expected false, but was " + value);
  },

  equal: function(expected, actual) {
    if (expected !== actual)
      this.fail("Expected " + this._printObject(expected) + " but received " + this._printObject(actual));
  },

  arrayEqual: function(expected, actual) {
    var isFailure = false;
    if (expected == null || expected.length !== actual.length)
      isFailure = true;
    for (var i = 0; !isFailure && i < expected.length; i++)
      if (expected[i] !== actual[i])
        isFailure = true;
    if (isFailure)
      this.fail("Expected " + this._printObject(expected) + " but received " + this._printObject(actual));
  },

  // It would be nice to call this 'throws', but all Java keywords are Javascript keywords and hence 'throws'
  // is a JS keyword. Sigh.
  throwsException: function(expression, expectedExceptionName) {
    try {
      expression();
    } catch(exception) {
      if (expectedExceptionName) {
        if (exception.name === expectedExceptionName) return;
        else {
          assert.fail("Expected exception " + expectedExceptionName + " to be thrown but exception " +
            exception.name + " was thrown instead.");
        }
      } else return;
    }
    if (expectedExceptionName)
      assert.fail("Expected exception " + expectedExceptionName + " but no exception was thrown.");
    else
      assert.fail("Expected exception but none was thrown.");
  },

  fail: function(message) { throw new AssertionError(message); },

  /* Used for printing the arguments passed to assertions. */
  _printObject: function(object) {
    if (object === null) return "null";
    else if (object === undefined) return "undefined";
    else if (typeof object === "string") return '"' + object + '"';
    else {
      try { return JSON.stringify(object); }
      catch (exception) {
        // object might not be stringifiable (e.g. DOM nodes), or JSON.stringify may not exist.
        return object.toString();
      }
    }
  }
};

/*
 * ensureCalled takes a function and ensures that it gets called by the end of the test case. This is
 * useful when you add callbacks to an object you're testing and you want to make sure they get called.
 */
scope.ensureCalled = function(toExecute) {
  var wrappedFunction = function() {
    var index = Tests.requiredCallbacks.indexOf(wrappedFunction);
    if (index >= 0)
      Tests.requiredCallbacks.splice(index, 1);
    if (toExecute)
      return toExecute.apply(null, arguments);
  };
  Tests.requiredCallbacks.push(wrappedFunction);
  return wrappedFunction;
};

scope.AssertionError = function(message) {
  this.name = AssertionError;
  this.message = message;
};
AssertionError.prototype = new Error();
AssertionError.prototype.constructor = AssertionError;


/*
 * A Context is a named set of test methods and nested contexts, with optional setup and tearDown blocks.
 * - contents: an array which can include a setup and tearDown method, test methods, and nested contexts.
 */
scope.Context = function(name, contents) {
  Context.nextId = Context.nextId || 0;
  this.id = Context.nextId;
  Context.nextId++;

  this.name = name;
  this.setupMethod = null;
  this.tearDownMethod = null;
  this.contexts = [];
  this.testMethods = [];

  for (var i = 0; i < contents.length; i++) {
    var testMethod = contents[i];
    if (testMethod instanceof SetupMethod)
      this.setupMethod = testMethod;
    else if (testMethod instanceof TearDownMethod)
      this.tearDownMethod = testMethod;
    else if (testMethod instanceof Context)
      this.contexts.push(testMethod);
    else
      this.testMethods.push(testMethod);
  }
};

/*
 * See the usage documentation for details on how to use the "context" and "should" functions.
 */
scope.context = function() {
  var newContext = new Context(arguments[0], Array.prototype.slice.call(arguments, 1));
  Tests.testContexts.push(newContext);
  return newContext;
};

scope.setup = function() { return new SetupMethod(arguments[0]); };
scope.SetupMethod = function(methodBody) { this.methodBody = methodBody; };

scope.tearDown = function() { return new TearDownMethod(arguments[0]); };
scope.TearDownMethod = function(methodBody) { this.methodBody = methodBody; };

scope.should = function(name, methodBody) { return new TestMethod(name, methodBody); };
scope.TestMethod = function(name, methodBody) {
  this.name = name;
  this.methodBody = methodBody;
};

/*
 * Tests is used to run tests and keep track of the success and failure counts.
 */
scope.Tests = {
  testContexts: [],
  completedContexts: [],
  testsRun: 0,
  testsFailed: 0,
  // This will be set to "console.log" when running in a browser, and "print" in Rhino or V8. Feel free
  // to override this to be your own output function.
  outputMethod: null,

  // The list of callbacks that the developer wants to ensure are called by the end of the test.
  // This is manipulated by the ensureCalled() function.
  requiredCallbacks: [],

  /*
   * Run all contexts which have been defined.
   * - testNameFilter: a String. If provided, only run tests which match testNameFilter will be run.
   */
  run: function(testNameFilter) {
    // Pick an output method based on whether we're running in a browser or via a command-line js shell.
    if (!Tests.outputMethod) {
      var isShell = (typeof(Envjs) !== "undefined") || (typeof("window") === "undefined");
      if (isShell)
        Tests.outputMethod = print;
      else if (typeof(console) != "undefined") // Available in browsers.
        Tests.outputMethod = function() { console.log.apply(console, arguments); };
      else
        Tests.outputMethod = print; // print is available in all command-line shells.
    }

    // Run all of the top level contexts (those not defined within another context) which will in turn run
    // any nested contexts. We know that the very last context ever added to Tests.testContexts is a top level
    // context. Also note that any contexts which have not already been run by a previous top level context
    // must themselves be top level contexts.
    Tests.testsRun = 0;
    Tests.testsFailed = 0;
    for (var i = Tests.testContexts.length - 1; i >= 0; i--) {
      var context = Tests.testContexts[i];
      var isTopLevelContext = !Tests.completedContexts[context.id];
      if (isTopLevelContext)
        Tests.runContext(context, [], testNameFilter);
    }
    Tests.printTestSummary();
  },

  /*
   * Run a context. This runs the test methods defined in the context first, and then any nested contexts.
   */
  runContext: function(context, parentContexts, testNameFilter) {
    Tests.completedContexts[context.id] = true;
    var testMethods = context.testMethods;
    parentContexts = parentContexts.concat([context]);
    for (var i = 0; i < context.testMethods.length; i++)
      Tests.runTest(context.testMethods[i], parentContexts, testNameFilter);
    for (var i = 0; i < context.contexts.length; i++)
      Tests.runContext(context.contexts[i], parentContexts, testNameFilter);
  },

  /*
   * Run a test method. This will run all setup methods in all contexts, and then all teardown methods.
   * - testMethod: the function to execute.
   * - contexts: an array of contexts, ordered outer to inner.
   * - testNameFilter: A String. If provided, only run the test if it matches the testNameFilter.
   */
  runTest: function(testMethod, contexts, testNameFilter) {
    var fullTestName = Tests.fullyQualifiedName(testMethod.name, contexts);
    if (testNameFilter && fullTestName.indexOf(testNameFilter) == -1)
      return;

    Tests.testsRun++;
    var failureMessage = null;
    // This is the scope which all references "this" in the setup and test methods will resolve to.
    var testScope = {};

    try {
      try {
        for (var i = 0; i < contexts.length; i++) {
          if (contexts[i].setupMethod)
            contexts[i].setupMethod.methodBody.apply(testScope);
        }
        testMethod.methodBody.apply(testScope);
      }
      finally {
        for (var i = 0; i < contexts.length; i++) {
          if (contexts[i].tearDownMethod)
            contexts[i].tearDownMethod.methodBody.apply(testScope);
        }
      }
    } catch(exception) {
      failureMessage = exception.toString();
      if (!(exception instanceof AssertionError) && exception.stack)
        failureMessage += ("\n" + exception.stack);
    }

    if (!failureMessage && Tests.requiredCallbacks.length > 0)
      failureMessage = "A callback function should have been called during this test, but it wasn't.";
    if (failureMessage) {
      Tests.testsFailed++;
      Tests.printFailure(fullTestName, failureMessage);
    }

    Tests.requiredCallbacks = [];
    Stubs.clearStubs();
  },

  /* The fully-qualified name of the test or context, e.g. "context1: context2: testName". */
  fullyQualifiedName: function(testName, contexts) {
    var contextNames = [];
    for (var i = 0; i < contexts.length; i++)
      contextNames.push(contexts[i].name);
    return contextNames.concat(testName).join(": ");
  },

  printTestSummary: function() {
    if (Tests.testsFailed > 0)
      this.outputMethod("Fail (" + Tests.testsFailed + "/" + Tests.testsRun + ")");
    else
      this.outputMethod("Pass (" + Tests.testsRun + "/" + Tests.testsRun + ")");
  },

  printFailure: function(testName, failureMessage) {
    // TODO(philc): We should consider other output formats, like HTML.
    this.outputMethod("Fail \"" + testName + "\" - ", failureMessage);
  }
};

/*
 * Stubs
 */

scope.stub = function(object, propertyName, returnValue) {
  Stubs.stubbedObjects.push( { object:object, propertyName: propertyName, original: object[propertyName] });
  object[propertyName] = returnValue;
};

/*
 * returns() is useful when you want to stub out a function (instead of a property) and you
 * want to hard code its return value, for example:
 * stubs(shoppingCart, "calculateTotal", returns(4.0))
 */
scope.returns = function(value) { return function() { return value; } };

Stubs = {
  stubbedObjects: [],

  clearStubs: function() {
    // Restore stubs in the reverse order they were defined in, in case the same property was stubbed twice.
    for (var i = Stubs.stubbedObjects.length - 1; i >= 0; i--) {
      var stubProperties = Stubs.stubbedObjects[i];
      stubProperties.object[stubProperties.propertyName] = stubProperties.original;
    }
  }
};
