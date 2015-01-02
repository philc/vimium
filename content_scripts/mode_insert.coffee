
class InsertMode extends Mode
  isInsertMode: false

  # Input or text elements are considered focusable and able to receieve their own keyboard events, and will
  # enter insert mode if focused. Also note that the "contentEditable" attribute can be set on any element
  # which makes it a rich text editor, like the notes on jjot.com.
  isEditable: (element) ->
    return true if element.isContentEditable
    nodeName = element.nodeName?.toLowerCase()
    # Use a blacklist instead of a whitelist because new form controls are still being implemented for html5.
    if nodeName == "input" and element.type and not element.type in ["radio", "checkbox"]
      return true
    nodeName in ["textarea", "select"]

  # Embedded elements like Flash and quicktime players can obtain focus but cannot be programmatically
  # unfocused.
  isEmbed: (element) ->
    element.nodeName?.toLowerCase() in ["embed", "object"]

  canEditElement: (element) ->
    element and (@isEditable(element) or @isEmbed element)

  # Check whether insert mode is active.  Also, activate insert mode if the current element is editable.
  isActive: ->
    return true if @isInsertMode
    # FIXME(smblott).  Is there a way to (safely) cache the results of these @canEditElement() calls?
    @activate() if @canEditElement document.activeElement
    @isInsertMode

  generateKeyHandler: (type) ->
    (event) =>
      return Mode.propagate unless @isActive()
      return handlerStack.passDirectlyToPage unless type == "keydown" and KeyboardUtils.isEscape event
      # We're now exiting insert mode.
      if @canEditElement event.srcElement
        # Remove the focus so the user can't just get himself back into insert mode by typing in the same input
        # box.
        # NOTE(smblott, 2014/12/22) Including embeds for .blur() here is experimental.  It appears to be the
        # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
        # games.  See discussion in #1211 and #1194.
        event.srcElement.blur()
      @isInsertMode = false
      Mode.updateBadge()
      Mode.suppressPropagation

  activate: ->
    @isInsertMode = true
    Mode.updateBadge()

  # Override (and re-use) updateBadgeForMode() from Mode.updateBadgeForMode().  Use insert-mode badge only if
  # we're active and no mode higher in stack has already inserted a badge.
  updateBadgeForMode: (badge) ->
    @badge = if @isActive() then "I" else ""
    super badge

  checkModeState: ->
    previousState = @isInsertMode
    if @isActive() != previousState
      Mode.updateBadge()

  constructor: ->
    super
      name: "insert"
      badge: "I"
      keydown: @generateKeyHandler "keydown"
      keypress: @generateKeyHandler "keypress"
      keyup: @generateKeyHandler "keyup"

    @handlers.push handlerStack.push
      DOMActivate: => @checkModeState()
      focus: => @checkModeState()
      blur: => @checkModeState()

    # We may already have been dropped into insert mode.  So check.
    Mode.updateBadge()

root = exports ? window
root.InsertMode = InsertMode
