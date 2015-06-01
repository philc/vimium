
$ = (id) -> document.getElementById id
bgExclusions = chrome.extension.getBackgroundPage().Exclusions

# We have to use Settings from the background page here (not Settings, directly) to avoid a race condition for
# the page popup.  Specifically, we must ensure that the settings have been updated on the background page
# *before* the popup closes.  This ensures that any exclusion-rule changes are in place before the page
# regains the focus.
bgSettings = chrome.extension.getBackgroundPage().Settings

#
# Class hierarchy for various types of option.
class Option
  # Base class for all option classes.
  # Abstract. Option does not define @populateElement or @readValueFromElement.

  # Static. Array of all options.
  @all = []

  constructor: (@field,@onUpdated) ->
    @element = $(@field)
    @element.addEventListener "change", @onUpdated
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
    if JSON.stringify value != JSON.stringify @previous
      bgSettings.set @field, @previous = value

  restoreToDefault: ->
    bgSettings.clear @field
    @fetch()

  # Static method.
  @saveOptions: ->
    Option.all.map (option) -> option.save()

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
  constructor: (args...) ->
    super(args...)
    @element.addEventListener "input", @onUpdated
  populateElement: (value) -> @element.value = value
  readValueFromElement: -> @element.value.trim()

class NonEmptyTextOption extends Option
  constructor: (args...) ->
    super(args...)
    @element.addEventListener "input", @onUpdated

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
      @addRule()

  # Add a new rule, focus its pattern, scroll it into view, and return the newly-added element.  On the
  # options page, there is no current URL, so there is no initial pattern.  This is the default.  On the popup
  # page (see ExclusionRulesOnPopupOption), the pattern is pre-populated based on the current tab's URL.
  addRule: (pattern="") ->
      element = @appendRule { pattern: pattern, passKeys: "" }
      @getPattern(element).focus()
      exclusionScrollBox = $("exclusionScrollBox")
      exclusionScrollBox.scrollTop = exclusionScrollBox.scrollHeight
      @onUpdated()
      element

  populateElement: (rules) ->
    for rule in rules
      @appendRule rule

  # Append a row for a new rule.  Return the newly-added element.
  appendRule: (rule) ->
    content = document.querySelector('#exclusionRuleTemplate').content
    row = document.importNode content, true

    for field in ["pattern", "passKeys"]
      element = row.querySelector ".#{field}"
      element.value = rule[field]
      for event in [ "input", "change" ]
        element.addEventListener event, @onUpdated

    @getRemoveButton(row).addEventListener "click", (event) =>
      rule = event.target.parentNode.parentNode
      rule.parentNode.removeChild rule
      @onUpdated()

    @element.appendChild row
    @element.children[@element.children.length-1]

  readValueFromElement: ->
    rules =
      for element in @element.getElementsByClassName "exclusionRuleTemplateInstance"
        pattern: @getPattern(element).value.trim()
        passKeys: @getPassKeys(element).value.trim()
    rules.filter (rule) -> rule.pattern

  # Accessors for the three main sub-elements of an "exclusionRuleTemplateInstance".
  getPattern: (element) -> element.querySelector(".pattern")
  getPassKeys: (element) -> element.querySelector(".passKeys")
  getRemoveButton: (element) -> element.querySelector(".exclusionRemoveButtonButton")

# ExclusionRulesOnPopupOption is ExclusionRulesOption, extended with some UI tweeks suitable for use in the
# page popup.  This also differs from ExclusionRulesOption in that, on the page popup, there is always a URL
# (@url) associated with the current tab.
class ExclusionRulesOnPopupOption extends ExclusionRulesOption
  constructor: (@url, args...) ->
    super(args...)

  addRule: ->
    element = super @generateDefaultPattern()
    @activatePatternWatcher element
    # ExclusionRulesOption.addRule()/super() has focused the pattern.  Here, focus the passKeys instead;
    # because, in the popup, we already have a pattern, so the user is more likely to edit the passKeys.
    @getPassKeys(element).focus()
    # Return element (for consistency with ExclusionRulesOption.addRule()).
    element

  populateElement: (rules) ->
    super(rules)
    elements = @element.getElementsByClassName "exclusionRuleTemplateInstance"
    @activatePatternWatcher element for element in elements

    haveMatch = false
    for element in elements
      pattern = @getPattern(element).value.trim()
      if 0 <= @url.search bgExclusions.RegexpCache.get pattern
        haveMatch = true
        @getPassKeys(element).focus()
      else
        element.style.display = 'none'
    @addRule() unless haveMatch

  # Provide visual feedback (make it red) when a pattern does not match the current tab's URL.
  activatePatternWatcher: (element) ->
    patternElement = element.children[0].firstChild
    patternElement.addEventListener "keyup", =>
      if @url.match bgExclusions.RegexpCache.get patternElement.value
        patternElement.title = patternElement.style.color = ""
      else
        patternElement.style.color = "red"
        patternElement.title = "Red text means that the pattern does not\nmatch the current URL."

  # Generate a default exclusion-rule pattern from a URL.  This is then used to pre-populate the pattern on
  # the page popup.
  generateDefaultPattern: ->
    if /^https?:\/\/./.test @url
      # The common use case is to disable Vimium at the domain level.
      # Generate "https?://www.example.com/*" from "http://www.example.com/path/to/page.html".
      "https?:/" + @url.split("/",3)[1..].join("/") + "/*"
    else if /^[a-z]{3,}:\/\/./.test @url
      # Anything else which seems to be a URL.
      @url.split("/",3).join("/") + "/*"
    else
      @url + "*"

initOptionsPage = ->
  onUpdated = ->
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
          $("advancedOptionsButton").innerHTML = "Show Advanced Options"
        else
          $("advancedOptions").style.display = "table-row-group"
          $("advancedOptionsButton").innerHTML = "Hide Advanced Options"
        advancedMode = !advancedMode
        $("advancedOptionsButton").blur()
        event.preventDefault()

  activateHelpDialog = ->
    showHelpDialog chrome.extension.getBackgroundPage().helpDialogHtml(true, true, "Command Listing"), frameId
    # Prevent the "show help" link from retaining the focus when clicked.
    document.activeElement.blur()

  saveOptions = ->
    Option.saveOptions()
    $("saveOptions").disabled = true
    $("saveOptions").innerHTML = "No Changes"

  $("saveOptions").addEventListener "click", saveOptions
  $("advancedOptionsButton").addEventListener "click", toggleAdvancedOptions
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
      saveOptions()

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
    grabBackFocus: CheckBoxOption
    searchEngines: TextOption
    searchUrl: NonEmptyTextOption
    userDefinedLinkHintCss: TextOption

  # Populate options. The constructor adds each new object to "Option.all".
  for name, type of options
    new type(name,onUpdated)

initPopupPage = ->
  chrome.tabs.getSelected null, (tab) ->
    exclusions = null
    document.getElementById("optionsLink").setAttribute "href", chrome.runtime.getURL("pages/options.html")

    # As the active URL, we choose the most recently registered URL from a frame in the tab, or the tab's own
    # URL.
    url = chrome.extension.getBackgroundPage().urlForTab[tab.id] || tab.url

    updateState = ->
      rule = bgExclusions.getRule url, exclusions.readValueFromElement()
      $("state").innerHTML = "Vimium will " +
        if rule and rule.passKeys
          "exclude <span class='code'>#{rule.passKeys}</span>"
        else if rule
          "be disabled"
        else
          "be enabled"

    onUpdated = ->
      $("helpText").innerHTML = "Type <strong>Ctrl-Enter</strong> to save and close."
      $("saveOptions").removeAttribute "disabled"
      $("saveOptions").innerHTML = "Save Changes"
      updateState() if exclusions

    saveOptions = ->
      Option.saveOptions()
      $("saveOptions").innerHTML = "Saved"
      $("saveOptions").disabled = true

    $("saveOptions").addEventListener "click", saveOptions

    document.addEventListener "keyup", (event) ->
      if event.ctrlKey and event.keyCode == 13
        saveOptions()
        window.close()

    # Populate options. Just one, here.
    exclusions = new ExclusionRulesOnPopupOption url, "exclusionRules", onUpdated

    updateState()
    document.addEventListener "keyup", updateState

#
# Initialization.
document.addEventListener "DOMContentLoaded", ->
  xhr = new XMLHttpRequest()
  xhr.open 'GET', chrome.extension.getURL('pages/exclusions.html'), true
  xhr.onreadystatechange = ->
    if xhr.readyState == 4
      $("exclusionScrollBox").innerHTML = xhr.responseText
      switch location.pathname
        when "/pages/options.html" then initOptionsPage()
        when "/pages/popup.html" then initPopupPage()

  xhr.send()

