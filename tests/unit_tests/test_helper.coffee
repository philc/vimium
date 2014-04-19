require("../shoulda.js/shoulda.js")
global.extend = (hash1, hash2) ->
  for key of hash2
    hash1[key] = hash2[key]
  hash1

# derived from https://github.com/davidchambers/Base64.js/blob/master/base64.js
global.btoa = (input) ->
  block = 0
  idx = 0
  map = chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
  output = ""
  while input.charAt(idx | 0) or (map = "=" and idx % 1)
    charCode = input.charCodeAt(idx += 3/4)
    if charCode > 0xFF
      throw "'btoa' failed: The string to be encoded contained non-Latin1 characters"
    output += map[63 & block >> 8 - idx % 1 * 8]
    block = block << 8 | charCode
  output
