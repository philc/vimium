$ = (id) -> document.getElementById id
bgSettings = chrome.extension.getBackgroundPage().Settings
Exclusions = chrome.extension.getBackgroundPage().Exclusions

#
# Class hierarchy for various types of option.
class Option
  # Base class for all option classes.
  # Abstract. Option does not define @populateElement or @readValueFromElement.

  # Static. Array of all options.
  @all = []

  constructor: (field,enableSaveButton) ->
    @field = field
    @onUpdated = enableSaveButton
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
    # These are only relevant on the options page; catch the exception on the popup page.
    try
      $("saveOptions").disabled = true
      $("saveOptions").innerHTML = "No Changes"

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
  populateElement: (value) -> @element.value = value
  readValueFromElement: -> @element.value.trim()

class NonEmptyTextOption extends Option
  constructor: (field,enableSaveButton) ->
    super(field,enableSaveButton)
    @element.addEventListener "input", enableSaveButton

  populateElement: (value) -> @element.value = value
  # If the new value is not empty, then return it. Otherwise, restore the default value.
  readValueFromElement: -> if value = @element.value.trim() then value else @restoreToDefault()

class CheckBoxOption extends Option
  populateElement: (value) -> @element.checked = value
  readValueFromElement: -> @element.checked

class ExclusionRulesOption extends Option
  constructor: (field, onUpdated, @url=null) ->
    super(field, onUpdated)
    $("exclusionAddButton").addEventListener "click", (event) =>
      @appendRule { pattern: "", passKeys: "" }
      # Focus the pattern element in the new rule.
      @element.children[@element.children.length-1].children[0].children[0].focus()
      # Scroll the new rule into view.
      exclusionScrollBox = $("exclusionScrollBox")
      exclusionScrollBox.scrollTop = exclusionScrollBox.scrollHeight

  populateElement: (rules) ->
    for rule in rules
      @appendRule rule

    # If this is the popup page (@url is defined), then hide rules which do not match @url.  If no rules
    # match, then add a default rule.
    if @url
      haveMatch = false
      for element in @element.getElementsByClassName "exclusionRuleTemplateInstance"
        pattern = element.children[0].firstChild.value.trim()
        unless @url.match Exclusions.RegexpCache.get pattern
          element.style.display = 'none'
          haveMatch = true

  # Append a row for a new rule.
  appendRule: (rule) ->
    content = document.querySelector('#exclusionRuleTemplate').content
    row = document.importNode content, true

    for field in ["pattern", "passKeys"]
      element = row.querySelector ".#{field}"
      element.value = rule[field]
      for event in [ "input", "change" ]
        element.addEventListener event, @onUpdated

    remove = row.querySelector ".exclusionRemoveButton"
    remove.addEventListener "click", (event) =>
      row = event.target.parentNode.parentNode
      row.parentNode.removeChild row
      @onUpdated()

    @element.appendChild row

  readValueFromElement: ->
    rules =
      for element in @element.getElementsByClassName "exclusionRuleTemplateInstance"
        pattern = element.children[0].firstChild.value.trim()
        passKeys = element.children[1].firstChild.value.trim()
        { pattern: pattern, passKeys: passKeys }
    rules.filter (rule) -> rule.pattern

  areEqual: (a,b) ->
    # Flatten each list of rules to a newline-separated string representation, and then use string equality.
    # This is correct because patterns and passKeys cannot themselves contain newlines.
    flatten = (rule) -> if rule and rule.pattern then rule.pattern + "\n" + rule.passKeys else ""
    a.map(flatten).join("\n") == b.map(flatten).join("\n")

#
# Operations for page elements.
enableSaveButton = ->
  $("saveOptions").removeAttribute "disabled"
  $("saveOptions").innerHTML = "Save Changes"

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
      # Prevent the "advanced options" link from retaining the focus.
      document.activeElement.blur()

activateHelpDialog = ->
  showHelpDialog chrome.extension.getBackgroundPage().helpDialogHtml(true, true, "Command Listing"), frameId
  # Prevent the "show help" link from retaining the focus.
  document.activeElement.blur()

initOptions = ->
  options =
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

  # Populate options.  The constructor adds each new object to "Option.all".
  for name, type of options
    new type(name,enableSaveButton)

  $("saveOptions").addEventListener "click", Option.saveOptions
  $("advancedOptionsLink").addEventListener "click", toggleAdvancedOptions
  $("showCommands").addEventListener "click", activateHelpDialog
  $("filterLinkHints").addEventListener "click", maintainLinkHintsView

  for element in document.getElementsByClassName "nonEmptyTextOption"
    element.className = element.className + " example info"
    element.innerHTML = "Leave empty to reset this option."

  maintainLinkHintsView()
  window.onbeforeunload = -> "You have unsaved changes to options." unless $("saveOptions").disabled

  document.addEventListener "keyup", (event) ->
    if event.ctrlKey and event.keyCode == 13
      document.activeElement.blur() if document?.activeElement?.blur
      Option.saveOptions()

initPopup = ->
  chrome.tabs.getSelected null, (tab) ->
    document.getElementById("optionsLink").setAttribute "href", chrome.runtime.getURL("pages/options.html")
    updated = false

    onUpdated = ->
      $("helpText").innerHTML = "Type <strong>Ctrl-Enter</strong> to save and close; <strong>Esc</strong> to cancel."
      updated = true

    document.addEventListener "keyup", (event) ->
      if event.ctrlKey and event.keyCode == 13
        Option.saveOptions()
        window.close()

    new ExclusionRulesOption("exclusionRules", onUpdated, tab.url)

#
# Initialization.
document.addEventListener "DOMContentLoaded", ->
  switch location.pathname
    when "/pages/options.html" then initOptions()
    when "/pages/popup.html" then initPopup()

