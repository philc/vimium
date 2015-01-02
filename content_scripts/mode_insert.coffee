
class InsertMode extends Mode
  isInsertMode: false

  # Input or text elements are considered focusable and able to receieve their own keyboard events, and will
  # enter insert mode if focused. Also note that the "contentEditable" attribute can be set on any element
  # which makes it a rich text editor, like the notes on jjot.com.
  isEditable: (element) ->
    return true if element.isContentEditable
    nodeName = element.nodeName?.toLowerCase()
    # Use a blacklist instead of a whitelist because new form controls are still being implemented for html5.
    if nodeName == "input" and element.type not in ["radio", "checkbox"]
      return true
    nodeName in ["textarea", "select"]

  # Embedded elements like Flash and quicktime players can obtain focus but cannot be programmatically
  # unfocused.
  isEmbed: (element) ->
    element.nodeName?.toLowerCase() in ["embed", "object"]

  isFocusable: (element) ->
    (@isEditable(element) or @isEmbed element)

  # Check whether insert mode is active.  Also, activate insert mode if the current element is content
  # editable.
  isActive: ->
    return true if @isInsertMode
    # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245); and
    # unfortunately, isEditable() is called *before* the change is made.  Therefore, we need to re-check
    # whether the active element is contentEditable.
    @activate() if document.activeElement?.isContentEditable
    @isInsertMode

  generateKeyHandler: (type) ->
    (event) =>
      return Mode.propagate unless @isActive()
      return handlerStack.passDirectlyToPage unless type == "keydown" and KeyboardUtils.isEscape event
      # We're now exiting insert mode.
      if @isEditable(event.srcElement) or @isEmbed event.srcElement
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
    unless @isInsertMode
      @isInsertMode = true
      Mode.updateBadge()

  # Override (and re-use) updateBadgeForMode() from Mode.updateBadgeForMode().  Use insert-mode badge only if
  # we're active and no mode higher in stack has already inserted a badge.
  updateBadgeForMode: (badge) ->
    @badge = if @isActive() then "I" else ""
    super badge

  constructor: ->
    super
      name: "insert"
      badge: "I"
      keydown: @generateKeyHandler "keydown"
      keypress: @generateKeyHandler "keypress"
      keyup: @generateKeyHandler "keyup"

    @handlers.push handlerStack.push
      focus: (event) =>
        handlerStack.alwaysPropagate =>
          if not @isInsertMode and @isFocusable event.target
            @activate()
      blur: (event) =>
        handlerStack.alwaysPropagate =>
          if @isInsertMode and @isFocusable event.target
            @isInsertMode = false
            Mode.updateBadge()

    # We may already have been dropped into insert mode.  So check.
    Mode.updateBadge()

root = exports ? window
root.InsertMode = InsertMode
