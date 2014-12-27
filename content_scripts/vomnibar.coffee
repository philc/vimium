#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
Vomnibar =
  vomnibarElement: null
  vomnibarPort: null

  activate: -> @open {completer:"omni"}
  activateInNewTab: -> @open {
    completer: "omni"
    selectFirst: false
    newTab: true
  }
  activateTabSelection: -> @open {
    completer: "tabs"
    selectFirst: true
  }
  activateBookmarks: -> @open {
    completer: "bookmarks"
    selectFirst: true
  }
  activateBookmarksInNewTab: -> @open {
    completer: "bookmarks"
    selectFirst: true
    newTab: true
  }
  activateEditUrl: -> @open {
    completer: "omni"
    selectFirst: false
    query: window.location.href
  }
  activateEditUrlInNewTab: -> @open {
    completer: "omni"
    selectFirst: false
    query: window.location.href
    newTab: true
  }

  init: ->
    unless @vomnibarElement?
      @vomnibarElement = document.createElement "iframe"
      @vomnibarElement.className = "vomnibarFrame"
      @vomnibarElement.seamless = "seamless"
      @vomnibarElement.src = chrome.runtime.getURL "pages/vomnibar.html"
      @vomnibarElement.addEventListener "load", => @openPort()
      document.documentElement.appendChild @vomnibarElement
      @hide()

  # Open a port and pass it to the Vomnibar iframe via window.postMessage. This port can then be used to
  # communicate with the Vomnibar.
  openPort: ->
    messageChannel = new MessageChannel()
    @vomnibarPort = messageChannel.port1
    @vomnibarPort.onmessage = (event) => @handleMessage event

    # Get iframeMessageSecret so the iframe can determine that our message isn't the page impersonating us.
    chrome.storage.local.get "iframeMessageSecret", ({iframeMessageSecret: secret}) =>
      # Pass messageChannel.port2 to the vomnibar iframe, so that we can communicate with it.
      @vomnibarElement.contentWindow.postMessage secret, chrome.runtime.getURL(""), [messageChannel.port2]

  handleMessage: (event) ->
    if event.data == "show"
      @show()
    else if event.data == "hide"
      @hide()

  # This function opens the vomnibar. It accepts options, a map with the values:
  #   completer   - The completer to fetch results from.
  #   query       - Optional. Text to prefill the Vomnibar with.
  #   selectFirst - Optional, boolean. Whether to select the first entry.
  #   newTab      - Optional, boolean. Whether to open the result in a new tab.
  open: (options) ->
    return @init() unless @vomnibarPort? # The vomnibar iframe hasn't finished initialising yet.

    @vomnibarPort.postMessage options
    @show()
    @vomnibarElement.focus()

  close: -> @hide()

  show: ->
    @vomnibarElement?.style.display = "block"

  hide: ->
    @vomnibarElement?.style.display = "none"

root = exports ? window
root.Vomnibar = Vomnibar
