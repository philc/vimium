
class InsertMode extends Mode
  userActivated: false

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

  isActive: ->
    @userActivated or @canEditElement document.activeElement

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
      @userActivated = false
      @updateBadge()
      Mode.suppressPropagation

  pickBadge: ->
    if @isActive() then "I" else ""

  updateBadge: ->
    badge = @badge
    @badge = @pickBadge()
    Mode.setBadge() if badge != @badge
    Mode.propagate

  activate: ->
    @userActivated = true
    @updateBadge()

  constructor: ->
    super
      name: "insert"
      badge: @pickBadge()
      keydown: @generateKeyHandler "keydown"
      keypress: @generateKeyHandler "keypress"
      keyup: @generateKeyHandler "keyup"

    handlerStack.push
      DOMActivate: => @updateBadge()
      focus: => @updateBadge()
      blur: => @updateBadge()

root = exports ? window
root.InsertMode = InsertMode
