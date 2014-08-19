Vomnibar =
  vomnibarElement: null

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

  open: (options) ->
    unless @vomnibarElement?
      @vomnibarElement = document.createElement "iframe"
      @vomnibarElement.className = "vomnibarFrame"
      @vomnibarElement.seamless = "seamless"
      @hide()

    options.frameId = frameId

    optionStrings = []
    for option of options
      if typeof options[option] == "boolean"
        optionStrings.push option if options[option]
      else
        optionStrings.push "#{option}=#{escape(options[option])}"

    @vomnibarElement.src = "#{chrome.runtime.getURL "pages/vomnibar.html"}?#{optionStrings.join "&"}"
    document.documentElement.appendChild @vomnibarElement

    @vomnibarElement.focus()

  close: ->
    @hide()
    @vomnibarElement?.remove()

  show: ->
    @vomnibarElement?.style.display = "block"

  hide: ->
    @vomnibarElement?.style.display = "none"

root = exports ? window
root.Vomnibar = Vomnibar
