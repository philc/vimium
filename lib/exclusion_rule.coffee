root = exports ? window

# Operations to build the DOM on the options page for a single exclusion rule.

root.ExclusionRule =

  # Build a DOM table row (a "tr") for this rule.
  buildRuleElement: (rule,enableSaveButton) ->
    pattern = @buildInput(enableSaveButton,rule.pattern,"URL pattern","pattern")
    passKeys = @buildInput(enableSaveButton,rule.passKeys,"Excluded keys","passKeys")
    row = document.createElement("tr")
    row.className = "exclusionRow"
    remove = document.createElement("input")
    remove.type = "button"
    remove.value = "\u2716" # A cross.
    remove.className = "exclusionRemoveButton"
    remove.addEventListener "click", ->
      row.parentNode.removeChild(row)
      enableSaveButton()
    row.appendChild(pattern)
    row.appendChild(passKeys)
    row.appendChild(remove)
    # NOTE: Since the order of exclusions matters, it would be nice to have "Move Up" and "Move Down" buttons,
    # too.  But this option is pretty cluttered already.
    row

  # Build DOM (a "td" containing an "input") for a single input element.
  buildInput: (enableSaveButton,value,placeholder,cls) ->
    input = document.createElement("input")
    input.setAttribute("placeholder",placeholder)
    input.type = "text"
    input.value = value
    input.className = cls
    input.addEventListener "keyup", enableSaveButton, false
    input.addEventListener "change", enableSaveButton, false
    container = document.createElement("td")
    container.appendChild(input)
    container

  # Build a new exclusion rule from the given element.  This is the reverse of the two methods above.
  extractRule: (element) ->
    patternElement = element.firstChild
    passKeysElement = patternElement.nextSibling
    pattern = patternElement.firstChild.value.trim()
    passKeys = passKeysElement.firstChild.value.trim()
    if pattern then { pattern: pattern, passKeys: passKeys } else null
