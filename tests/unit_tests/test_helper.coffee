global.extend = (hash1, hash2) ->
  for own key of hash2
    hash1[key] = hash2[key]
  hash1

global.assert = require "assert"
global.setup = beforeEach
global.tearDown = afterEach
global.should = it

assert.isTrue = assert.ok
assert.isFalse = (value) -> assert.ok !value
assert.arrayEqual = assert.deepEqual

# Derived from shoulda.js.
global.returns = (value) -> -> value
global.stub = (object, propertyName, returnValue) ->
  original = object[propertyName]
  object[propertyName] = returnValue
  after -> object[propertyName] = original
