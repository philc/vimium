# Your content-script handlers go here.
# sendResponse() *must* be called.

chrome.runtime.onMessage.addListener (request, sender, sendResponse) ->
  switch request.name
    when "sayHello"
      alert "Hello!"
      sendResponse status: "ok"
    else
      sendResponse status: "no such content-script command"
