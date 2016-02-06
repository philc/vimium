# Content script handlers go here.

chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
  switch request.name
    when "alert"
      alert "Hello"
      sendResponse()
  false
