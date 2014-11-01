#
# This wraps the vomnibar iframe, which we inject into the page to provide the vomnibar.
#
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

  # This function opens the vomnibar. It accepts options, a map with the values:
  #   completer   - The completer to fetch results from.
  #   query       - Optional. Text to prefill the Vomnibar with.
  #   selectFirst - Optional, boolean. Whether to select the first entry.
  #   newTab      - Optional, boolean. Whether to open the result in a new tab.
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
