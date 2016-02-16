require("../shoulda.js/shoulda.js")
global.extend = (hash1, hash2) ->
  for own key of hash2
    hash1[key] = hash2[key]
  hash1
