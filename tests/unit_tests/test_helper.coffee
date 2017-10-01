root = global ? window

root.extend = (hash1, hash2) ->
  for own key of hash2
    hash1[key] = hash2[key]
  hash1

root.assert ?= require "assert"
root.setup = beforeEach
root.tearDown = afterEach
root.should = it

assert.isTrue = assert.ok
assert.isFalse = (value) -> assert.ok !value
assert.arrayEqual = assert.deepEqual

# Derived from shoulda.js.
root.returns = (value) -> -> value
root.stub = (object, propertyName, returnValue) ->
  original = object[propertyName]
  object[propertyName] = returnValue
  after -> object[propertyName] = original
