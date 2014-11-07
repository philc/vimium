
$ = (id) -> document.getElementById id
bgSettings = chrome.extension.getBackgroundPage().Settings

#
# Class hierarchy for various types of option.
class Option
  # Base class for all option classes.
  # Abstract. Option does not define @populateElement or @readValueFromElement.

  # Static. Array of all options.
  @all = []

  constructor: (field,enableSaveButton) ->
    @field = field
    @element = $(@field)
    @element.addEventListener "change", enableSaveButton
    @fetch()
    Option.all.push @

  # Fetch a setting from localStorage, remember the @previous value and populate the DOM element.
  # Return the fetched value.
  fetch: ->
    @populateElement @previous = bgSettings.get @field
    @previous

  # Write this option's new value back to localStorage, if necessary.
  save: ->
    value = @readValueFromElement()
    if not @areEqual value, @previous
      bgSettings.set @field, @previous = value
      bgSettings.performPostUpdateHook @field, value

  # Compare values; this is overridden by sub-classes.
  areEqual: (a,b) -> a == b

  restoreToDefault: ->
    bgSettings.clear @field
    @fetch()

  # Static method.
  @saveOptions: ->
    Option.all.map (option) -> option.save()
    $("saveOptions").disabled = true

  # Used by text options. <ctrl-Enter> saves all options.
  activateCtrlEnterListener: (element) ->
    element.addEventListener "keyup", (event) ->
      if event.ctrlKey and event.keyCode == 13
        element.blur()
        Option.saveOptions()

  # Abstract method; only implemented in sub-classes.
  # Populate the option's DOM element (@element) with the setting's current value.
  # populateElement: (value) -> DO_SOMETHING

  # Abstract method; only implemented in sub-classes.
  # Extract the setting's new value from the option's DOM element (@element).
  # readValueFromElement: -> RETURN_SOMETHING

class NumberOption extends Option
  populateElement: (value) -> @element.value = value
  readValueFromElement: -> parseFloat @element.value

class TextOption extends Option
  constructor: (field,enableSaveButton) ->
    super(field,enableSaveButton)
    @element.addEventListener "input", enableSaveButton
    @activateCtrlEnterListener @element
  populateElement: (value) -> @element.value = value
  readValueFromElement: -> @element.value.trim()

class NonEmptyTextOption extends Option
  constructor: (field,enableSaveButton) ->
    super(field,enableSaveButton)
    @element.addEventListener "input", enableSaveButton
    @activateCtrlEnterListener @element

  populateElement: (value) -> @element.value = value
  # If the new value is not empty, then return it. Otherwise, restore the default value.
  readValueFromElement: -> if value = @element.value.trim() then value else @restoreToDefault()

class CheckBoxOption extends Option
  populateElement: (value) -> @element.checked = value
  readValueFromElement: -> @element.checked

class ExclusionRulesOption extends Option
  constructor: (args...) ->
    super(args...)
    $("exclusionAddButton").addEventListener "click", (event) =>
      @appendRule { pattern: "", passKeys: "" }
      @maintainExclusionMargin()
      # Focus the pattern element in the new rule.
      @element.children[@element.children.length-1].children[0].children[0].focus()
      # Scroll the new rule into view.
      exclusionScrollBox = $("exclusionScrollBox")
      exclusionScrollBox.scrollTop = exclusionScrollBox.scrollHeight

  populateElement: (rules) ->
    while @element.firstChild
      @element.removeChild @element.firstChild
    for rule in rules
      @appendRule rule
    @maintainExclusionMargin()

  # Append a row for a new rule.
  appendRule: (rule) ->
    content = document.querySelector('#exclusionRuleTemplate').content
    row = document.importNode content, true

    for field in ["pattern", "passKeys"]
      element = row.querySelector ".#{field}"
      element.value = rule[field]
      @activateCtrlEnterListener element
      for event in [ "input", "change" ]
        element.addEventListener event, enableSaveButton

    remove = row.querySelector ".exclusionRemoveButton"
    remove.addEventListener "click", (event) =>
      row = event.target.parentNode.parentNode
      row.parentNode.removeChild row
      enableSaveButton()
      @maintainExclusionMargin()

    @element.appendChild row

  readValueFromElement: ->
    rules =
      for element in @element.children
        pattern = element.children[0].firstChild.value.trim()
        passKeys = element.children[1].firstChild.value.trim()
        { pattern: pattern, passKeys: passKeys }
    rules.filter (rule) -> rule.pattern

  areEqual: (a,b) ->
    # Flatten each list of rules to a newline-separated string representation, and then use string equality.
    # This is correct because patterns and passKeys cannot themselves contain newlines.
    flatten = (rule) -> if rule and rule.pattern then rule.pattern + "\n" + rule.passKeys else ""
    a.map(flatten).join("\n") == b.map(flatten).join("\n")

  # Hack.  There has to be a better way than...
  # The y-axis scrollbar for "exclusionRules" is only displayed if it is needed.  When visible, it appears on
  # top of the enclosed content (partially obscuring it).  Here, we adjust the margin of the "Remove" button to
  # compensate.
  maintainExclusionMargin: ->
    scrollBox = $("exclusionScrollBox")
    margin = if scrollBox.clientHeight < scrollBox.scrollHeight then "16px" else "0px"
    for element in scrollBox.getElementsByClassName "exclusionRemoveButton"
      element.style["margin-right"] = margin

#
# Operations for page elements.
enableSaveButton = ->
  $("saveOptions").removeAttribute "disabled"

# Display either "linkHintNumbers" or "linkHintCharacters", depending upon "filterLinkHints".
maintainLinkHintsView = ->
  hide = (el) -> el.parentNode.parentNode.style.display = "none"
  show = (el) -> el.parentNode.parentNode.style.display = "table-row"
  if $("filterLinkHints").checked
    hide $("linkHintCharacters")
    show $("linkHintNumbers")
  else
    show $("linkHintCharacters")
    hide $("linkHintNumbers")

toggleAdvancedOptions =
  do (advancedMode=false) ->
    (event) ->
      if advancedMode
        $("advancedOptions").style.display = "none"
        $("advancedOptionsLink").innerHTML = "Show advanced options&hellip;"
      else
        $("advancedOptions").style.display = "table-row-group"
        $("advancedOptionsLink").innerHTML = "Hide advanced options"
      advancedMode = !advancedMode
      event.preventDefault()

activateHelpDialog = ->
  showHelpDialog chrome.extension.getBackgroundPage().helpDialogHtml(true, true, "Command Listing"), frameId

#
# Initialization.
document.addEventListener "DOMContentLoaded", ->

  # Populate options.  The constructor adds each new object to "Option.all".
  new type(name,enableSaveButton) for name, type of {
    exclusionRules: ExclusionRulesOption
    filterLinkHints: CheckBoxOption
    hideHud: CheckBoxOption
    keyMappings: TextOption
    linkHintCharacters: NonEmptyTextOption
    linkHintNumbers: NonEmptyTextOption
    newTabUrl: NonEmptyTextOption
    nextPatterns: NonEmptyTextOption
    previousPatterns: NonEmptyTextOption
    regexFindMode: CheckBoxOption
    scrollStepSize: NumberOption
    smoothScroll: CheckBoxOption
    searchEngines: TextOption
    searchUrl: NonEmptyTextOption
    userDefinedLinkHintCss: TextOption
  }

  $("saveOptions").addEventListener "click", Option.saveOptions
  $("advancedOptionsLink").addEventListener "click", toggleAdvancedOptions
  $("showCommands").addEventListener "click", activateHelpDialog
  $("filterLinkHints").addEventListener "click", maintainLinkHintsView

  for element in document.getElementsByClassName "nonEmptyTextOption"
    element.className = element.className + " example info"
    element.innerHTML = "Leave empty to reset this option."

  maintainLinkHintsView()
  window.onbeforeunload = -> "You have unsaved changes to options." unless $("saveOptions").disabled

