
# Input or text elements are considered focusable and able to receieve their own keyboard events, and will
# enter insert mode if focused. Also note that the "contentEditable" attribute can be set on any element
# which makes it a rich text editor, like the notes on jjot.com.
isEditable =(element) ->
  return true if element.isContentEditable
  nodeName = element.nodeName?.toLowerCase()
  # Use a blacklist instead of a whitelist because new form controls are still being implemented for html5.
  if nodeName == "input" and element.type not in ["radio", "checkbox"]
    return true
  nodeName in ["textarea", "select"]

# Embedded elements like Flash and quicktime players can obtain focus.
isEmbed =(element) ->
  element.nodeName?.toLowerCase() in ["embed", "object"]

isFocusable =(element) ->
  isEditable(element) or isEmbed element

# Automatically trigger insert mode:
#   - On a keydown event in a contentEditable element.
#   - When a focusable element receives the focus.
#
# This mode is permanently installed fairly low down on the handler stack.
class InsertModeTrigger extends Mode
  constructor: ->
    super
      name: "insert-trigger"
      keydown: (event) =>
        return @continueBubbling if InsertModeTrigger.isSuppressed()
        # Some sites (e.g. inbox.google.com) change the contentEditable attribute on the fly (see #1245);
        # and unfortunately, the focus event happens *before* the change is made.  Therefore, we need to
        # check again whether the active element is contentEditable.
        return @continueBubbling unless document.activeElement?.isContentEditable
        new InsertMode document.activeElement
        @stopBubblingAndTrue

    @push
      focus: (event) =>
        @alwaysContinueBubbling =>
          return @continueBubbling if InsertModeTrigger.isSuppressed()
          return if not isFocusable event.target
          new InsertMode event.target

    # We may already have focussed an input, so check.
    new InsertMode document.activeElement if document.activeElement and isEditable document.activeElement

  # Allow other modes (notably InsertModeBlocker, below) to suppress this trigger. All static.
  @suppressors: 0
  @isSuppressed: -> 0 < @suppressors
  @suppress: -> @suppressors += 1
  @unsuppress: -> @suppressors -= 1

# Suppresses InsertModeTrigger.  This is used by various modes (usually by inheritance) to prevent
# unintentionally dropping into insert mode on focusable elements.
class InsertModeBlocker extends Mode
  constructor: (options = {}) ->
    InsertModeTrigger.suppress()
    options.name ||= "insert-blocker"
    super options

  exit: ->
    super()
    InsertModeTrigger.unsuppress()

# This mode is installed when insert mode is active.
class InsertMode extends Mode
  constructor: (@insertModeLock = null) ->
    super
      name: "insert"
      badge: "I"
      singleton: InsertMode
      keydown: (event) => @stopBubblingAndTrue
      keypress: (event) => @stopBubblingAndTrue
      keyup: (event) => @stopBubblingAndTrue
      exitOnEscape: true
      exitOnBlur: @insertModeLock

  exit: (event = null) ->
    super()
    element = event?.srcElement
    if element and isFocusable element
      # Remove the focus so the user can't just get himself back into insert mode by typing in the same
      # input box.
      # NOTE(smblott, 2014/12/22) Including embeds for .blur() here is experimental.  It appears to be the
      # right thing to do for most common use cases.  However, it could also cripple flash-based sites and
      # games.  See discussion in #1211 and #1194.
      element.blur()

root = exports ? window
root.InsertMode = InsertMode
root.InsertModeTrigger = InsertModeTrigger
root.InsertModeBlocker = InsertModeBlocker
