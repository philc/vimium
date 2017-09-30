global.extend = (hash1, hash2) ->
  for own key of hash2
    hash1[key] = hash2[key]
  hash1

global.assert = require "assert"
global.setup = beforeEach
global.tearDown = afterEach
global.should = it
