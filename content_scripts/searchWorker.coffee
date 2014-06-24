self.addEventListener "message", (event) ->
  text = event.data.text
  regex = event.data.regex

  regexMatches = text.match regex

  postData =
    regexMatches: regexMatches
  self.postMessage postData
, false
