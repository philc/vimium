#
# This implements link hinting. Typing "F" will enter link-hinting mode, where all clickable items on the
# page have a hint marker displayed containing a sequence of letters. Typing those letters will select a link.
#
# In our 'default' mode, the characters we use to show link hints are a user-configurable option. By default
# they're the home row.  The CSS which is used on the link hints is also a configurable option.
#
# In 'filter' mode, our link hints are numbers, and the user can narrow down the range of possibilities by
# typing the text of the link itself.
#
OPEN_IN_CURRENT_TAB = {}
OPEN_IN_NEW_BG_TAB = {}
OPEN_IN_NEW_FG_TAB = {}
OPEN_WITH_QUEUE = {}
COPY_LINK_URL = {}
OPEN_INCOGNITO = {}

LinkHints =
  hintMarkerContainingDiv: null
  # one of the enums listed at the top of this file
  hintMarkers: null
  mode: undefined
  # function that does the appropriate action on the selected link
  linkActivator: undefined
  # While in delayMode, all keypresses have no effect.
  delayMode: false
  # Handle the link hinting marker generation and matching. Must be initialized after settings have been
  # loaded, so that we can retrieve the option setting.
  getMarkerMatcher: ->
    if settings.get("filterLinkHints") then filterHints else alphabetHints
  # Lock to ensure only one instance runs at a time.
  isActive: false
  # Port to communicate with the link hint oracle in the background.
  port: null
  # Callback for deactivateMode. Set in setOpenLinkMode.
  deactivateModeCallback: null
  # Show HUD if we are the top frame.
  # TODO(mrmr1993): Fix this for pages with a top-level frameset.
  showHUD: -> HUD.show.apply(HUD, arguments) if window.top == window

  #
  # To be called after linkHints has been generated from linkHintsBase.
  #
  init: ->

  #
  # Generate an XPath describing what a clickable element is.
  # The final expression will be something like "//button | //xhtml:button | ..."
  # We use translate() instead of lower-case() because Chrome only supports XPath 1.0.
  #
  clickableElementsXPath: DomUtils.makeXPath(
    ["a", "area[@href]", "textarea", "button", "select",
     "input[not(@type='hidden' or @disabled or @readonly)]",
     "*[@onclick or @tabindex or @role='link' or @role='button' or contains(@class, 'button') or " +
     "@contenteditable='' or translate(@contenteditable, 'TRUE', 'true')='true']"])

  # We need this as a top-level function because our command system doesn't yet support arguments.
  activateModeToOpenInNewTab: -> @activateMode(OPEN_IN_NEW_BG_TAB)
  activateModeToOpenInNewForegroundTab: -> @activateMode(OPEN_IN_NEW_FG_TAB)
  activateModeToCopyLinkUrl: -> @activateMode(COPY_LINK_URL)
  activateModeWithQueue: -> @activateMode(OPEN_WITH_QUEUE)
  activateModeToOpenIncognito: -> @activateMode(OPEN_INCOGNITO)

  activateMode: (mode = OPEN_IN_CURRENT_TAB) ->
    # we need documentElement to be ready in order to append links
    return unless document.documentElement

    if @isActive
      return
    @isActive = true

    @setOpenLinkMode(mode)
    @hintMarkers = (@createMarkerFor(el) for el in @getVisibleClickableElements())

    @port = chrome.runtime.connect({ name: "linkHints" })
    @port.onMessage.addListener((response, port) => @onPortResponse(response, port))

    hintInformation = @getMarkerMatcher().getInformation(@hintMarkers)
    @port.postMessage({
      name: "registerLinkHints"
      hintInformation: hintInformation
      frameId: frameId
    })

    # Note(philc): Append these markers as top level children instead of as child nodes to the link itself,
    # because some clickable elements cannot contain children, e.g. submit buttons. This has the caveat
    # that if you scroll the page and the link has position=fixed, the marker will not stay fixed.
    @hintMarkerContainingDiv = DomUtils.createContainerForElementList(@hintMarkers,
      { id: "vimiumHintMarkerContainer", className: "vimiumReset" })

    # handlerStack is declared by vimium_frontend.coffee
    @handlerId = handlerStack.push({
      keydown: (event) =>
        return if @delayMode
        @port.postMessage({
          name: "handleKeyDown"
          event: DomUtils.jsonableEvent(event)
          frameId: frameId
        })
        false
      # trap all key events
      keypress: -> false
      keyup: -> false
    })

  setOpenLinkMode: (@mode) ->
    @deactivateModeCallback = null
    if @mode is OPEN_IN_NEW_BG_TAB or @mode is OPEN_IN_NEW_FG_TAB or @mode is OPEN_WITH_QUEUE
      if @mode is OPEN_IN_NEW_BG_TAB
        @showHUD("Open link in new tab")
      else if @mode is OPEN_IN_NEW_FG_TAB
        @showHUD("Open link in new tab and switch to it")
      else
        @deactivateModeCallback = (=> @activateModeWithQueue())
        @showHUD("Open multiple links in a new tab")
      @linkActivator = (link) ->
        # When "clicking" on a link, dispatch the event with the appropriate meta key (CMD on Mac, CTRL on
        # windows) to open it in a new tab if necessary.
        DomUtils.simulateClick(link, {
          shiftKey: @mode is OPEN_IN_NEW_FG_TAB,
          metaKey: KeyboardUtils.platform == "Mac",
          ctrlKey: KeyboardUtils.platform != "Mac" })
    else if @mode is COPY_LINK_URL
      @showHUD("Copy link URL to Clipboard")
      @linkActivator = (link) ->
        chrome.runtime.sendMessage({handler: "copyToClipboard", data: link.href})
    else if @mode is OPEN_INCOGNITO
      @showHUD("Open link in incognito window")

      @linkActivator = (link) ->
        chrome.runtime.sendMessage(
          handler: 'openUrlInIncognito'
          url: link.href)
    else # OPEN_IN_CURRENT_TAB
      @showHUD("Open link in current tab")
      @linkActivator = (link) -> DomUtils.simulateClick.bind(DomUtils, link)()

  #
  # Creates a link marker for the given link.
  #
  createMarkerFor: (link) ->
    marker = document.createElement("div")
    marker.className = "vimiumReset internalVimiumHintMarker vimiumHintMarker"
    marker.clickableItem = link.element

    clientRect = link.rect
    marker.style.left = clientRect.left + window.scrollX + "px"
    marker.style.top = clientRect.top  + window.scrollY  + "px"

    marker.rect = link.rect

    marker

  #
  # Returns all clickable elements that are not hidden and are in the current viewport.
  # We prune invisible elements partly for performance reasons, but moreso it's to decrease the number
  # of digits needed to enumerate all of the links on screen.
  #
  getVisibleClickableElements: ->
    resultSet = DomUtils.evaluateXPath(@clickableElementsXPath, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE)

    visibleElements = []

    # Find all visible clickable elements.
    for i in [0...resultSet.snapshotLength] by 1
      element = resultSet.snapshotItem(i)
      clientRect = DomUtils.getVisibleClientRect(element, clientRect)
      if (clientRect != null)
        visibleElements.push({element: element, rect: clientRect})

      if (element.localName == "area")
        map = element.parentElement
        continue unless map
        img = document.querySelector("img[usemap='#" + map.getAttribute("name") + "']")
        continue unless img
        imgClientRects = img.getClientRects()
        continue if (imgClientRects.length == 0)
        c = element.coords.split(/,/)
        coords = [parseInt(c[0], 10), parseInt(c[1], 10), parseInt(c[2], 10), parseInt(c[3], 10)]
        rect = {
          top: imgClientRects[0].top + coords[1],
          left: imgClientRects[0].left + coords[0],
          right: imgClientRects[0].left + coords[2],
          bottom: imgClientRects[0].top + coords[3],
          width: coords[2] - coords[0],
          height: coords[3] - coords[1]
        }

        visibleElements.push({element: element, rect: rect})

    visibleElements

  #
  # Handles port responses from the link hint oracle.
  #
  onPortResponse: (response, port) ->
    handler = null
    switch response.name
      when "setHintStrings"
        @setHintStrings(response, port)
      when "handleKeyDown"
        @handleKeyDown(response, port)
      when "updateVisibleHints"
        @updateVisibleHints(response, port)
      when "linkActivate"
        @linkActivate(response, port)
      when "deactivate"
        @deactivateModeCallback = null
        @deactivateMode(response.delay)

  setHintStrings: (response, port) ->
    @getMarkerMatcher().fillInMarkers(@hintMarkers, response.hintStrings)
    document.documentElement.appendChild(@hintMarkerContainingDiv)

  #
  # Handles ctrl and shift keys. The other keys are handled in the background page.
  #
  handleKeyDown: (response, port) ->
    {event} = response
    if (@mode == OPEN_IN_CURRENT_TAB or
        @mode == OPEN_IN_NEW_BG_TAB or
        @mode == OPEN_IN_NEW_FG_TAB)
      # Toggle whether to open link in a new or current tab.
      if event.keyCode == keyCodes.shiftKey
        @setOpenLinkMode(if @mode is OPEN_IN_CURRENT_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_CURRENT_TAB)

      else # event.keyCode == keyCodes.ctrlKey
        @setOpenLinkMode(if @mode is OPEN_IN_NEW_FG_TAB then OPEN_IN_NEW_BG_TAB else OPEN_IN_NEW_FG_TAB)

  updateVisibleHints: (response, port) ->
    {hintKeystrokeQueue, matchedInfo: {matched, updatedHintStrings, hintVisibles}} = response
    matchedMarkers = matched.map((index) => @hintMarkers[index])
    @getMarkerMatcher().fillInMarkers(matchedMarkers, updatedHintStrings)
    for marker, idx in @hintMarkers
      if (hintVisibles[idx])
        @showMarker(marker, hintKeystrokeQueue.length)
      else
        @hideMarker(marker)

  #
  # When only one link hint remains, this function activates it in the appropriate way.
  #
  linkActivate: (response, port) ->
    {delay, match} = response
    @delayMode = true
    if match? # This is the frame with the match.
      matchedLink = @hintMarkers[match]
      clickEl = matchedLink.clickableItem
      callback = (=> @delayMode = false)
      if (DomUtils.isSelectable(clickEl))
        DomUtils.simulateSelect(clickEl)
      else
        # TODO figure out which other input elements should not receive focus
        if (clickEl.nodeName.toLowerCase() == "input" && clickEl.type != "button")
          clickEl.focus()
        DomUtils.flashRect(matchedLink.rect)
        @linkActivator(clickEl)
    @deactivateMode(delay, (=> @delayMode = false))

  #
  # Shows the marker, highlighting matchingCharCount characters.
  #
  showMarker: (linkMarker, matchingCharCount) ->
    linkMarker.style.display = ""
    for j in [0...linkMarker.childNodes.length] by 1
      if (j < matchingCharCount)
        linkMarker.childNodes[j].classList.add("matchingCharacter")
      else
        linkMarker.childNodes[j].classList.remove("matchingCharacter")

  hideMarker: (linkMarker) -> linkMarker.style.display = "none"

  #
  # If called without arguments, it executes immediately.  Othewise, it
  # executes after 'delay' and invokes 'callback' when it is finished.
  #
  deactivateMode: (delay, callback) ->
    deactivate = =>
      if (@getMarkerMatcher().deactivate)
        @getMarkerMatcher().deactivate()
      if (@hintMarkerContainingDiv? and @hintMarkerContainingDiv.parentNode?)
        DomUtils.removeElement LinkHints.hintMarkerContainingDiv
      LinkHints.hintMarkerContainingDiv = null
      handlerStack.remove @handlerId
      HUD.hide()
      @isActive = false
      callback?()
      @deactivateModeCallback?()

    # we invoke the deactivate() function directly instead of using setTimeout(callback, 0) so that
    # deactivateMode can be tested synchronously
    if (!delay)
      deactivate()
    else
      setTimeout(deactivate, delay)

alphabetHints =
  getInformation: (hintMarkers) ->
    {
      count: hintMarkers.length
    }

  fillInMarkers: (hintMarkers, hintStrings) ->
    for marker, idx in hintMarkers
      hintString = hintStrings[idx]
      marker.innerHTML = spanWrap(hintString.toUpperCase())

    hintMarkers

filterHints =
  labelMap: {}

  #
  # Generate a map of input element => label
  #
  generateLabelMap: ->
    labels = document.querySelectorAll("label")
    for label in labels
      forElement = label.getAttribute("for")
      if (forElement)
        labelText = label.textContent.trim()
        # remove trailing : commonly found in labels
        if (labelText[labelText.length-1] == ":")
          labelText = labelText.substr(0, labelText.length-1)
        @labelMap[forElement] = labelText

  generateLinkText: (element) ->
    linkText = ""
    showLinkText = false
    # toLowerCase is necessary as html documents return "IMG" and xhtml documents return "img"
    nodeName = element.nodeName.toLowerCase()

    if (nodeName == "input")
      if (@labelMap[element.id])
        linkText = @labelMap[element.id]
        showLinkText = true
      else if (element.type != "password")
        linkText = element.value
        if not linkText and 'placeholder' of element
          linkText = element.placeholder
      # check if there is an image embedded in the <a> tag
    else if (nodeName == "a" && !element.textContent.trim() &&
        element.firstElementChild &&
        element.firstElementChild.nodeName.toLowerCase() == "img")
      linkText = element.firstElementChild.alt || element.firstElementChild.title
      showLinkText = true if (linkText)
    else
      linkText = element.textContent || element.innerHTML

    { text: linkText, show: showLinkText }

  getInformation: (hintMarkers) ->
    @generateLabelMap()

    linkTexts = []
    showLinkTexts = []

    for marker, idx in hintMarkers
      linkTextObject = @generateLinkText(marker.clickableItem)
      linkTexts.push(linkTextObject.text)
      showLinkTexts.push(linkTextObject.show)

    {
      linkTexts: linkTexts
      showLinkTexts: showLinkTexts
    }

  fillInMarkers: (hintMarkers, hintStrings) ->
    for marker, idx in hintMarkers
      hintString = hintStrings[idx]
      marker.innerHTML = spanWrap(hintString)

    hintMarkers

  deactivate: (delay, callback) ->
    @labelMap = {}

#
# Make each hint character a span, so that we can highlight the typed characters as you type them.
#
spanWrap = (hintString) ->
  innerHTML = []
  for char in hintString
    innerHTML.push("<span class='vimiumReset'>" + char + "</span>")
  innerHTML.join("")

root = exports ? window
root.LinkHints = LinkHints
