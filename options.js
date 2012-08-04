$ = function(id) { return document.getElementById(id); };
var bgSettings = chrome.extension.getBackgroundPage().Settings;

var editableFields = ["scrollStepSize", "excludedUrls", "linkHintCharacters", "userDefinedLinkHintCss",
                      "keyMappings", "filterLinkHints", "previousPatterns", "nextPatterns", "hideHud"];

var canBeEmptyFields = ["excludedUrls", "keyMappings", "userDefinedLinkHintCss"];

var postSaveHooks = {
  keyMappings: function (value) {
    commands = chrome.extension.getBackgroundPage().Commands;
    commands.clearKeyMappingsAndSetDefaults();
    commands.parseCustomKeyMappings(value);
    chrome.extension.getBackgroundPage().refreshCompletionKeysAfterMappingSave();
  }
};

document.addEventListener("DOMContentLoaded", function() {
  populateOptions();

  for (var i = 0; i < editableFields.length; i++) {
    $(editableFields[i]).addEventListener("keyup", onOptionKeyup, false);
    $(editableFields[i]).addEventListener("change", enableSaveButton, false);
    $(editableFields[i]).addEventListener("change", onDataLoaded, false);
  }

  $("advancedOptions").addEventListener("click", openAdvancedOptions, false);
  $("showCommands").addEventListener("click", function () {
    showHelpDialog(
      chrome.extension.getBackgroundPage().helpDialogHtml(true, true, "Command Listing"), frameId);
  }, false);

  document.getElementById("restoreSettings").addEventListener("click", restoreToDefaults);
  document.getElementById("saveOptions").addEventListener("click", saveOptions);
});

function onOptionKeyup(event) {
  if (event.target.getAttribute("type") !== "checkbox" &&
      event.target.getAttribute("savedValue") != event.target.value)
    enableSaveButton();
}

function onDataLoaded() {
  $("linkHintCharacters").readOnly = $("filterLinkHints").checked;
}

function enableSaveButton() { $("saveOptions").removeAttribute("disabled"); }

// Saves options to localStorage.
function saveOptions() {
  // If the value is unchanged from the default, delete the preference from localStorage; this gives us
  // the freedom to change the defaults in the future.
  for (var i = 0; i < editableFields.length; i++) {
    var fieldName = editableFields[i];
    var field = $(fieldName);

    var fieldValue;
    if (field.getAttribute("type") == "checkbox") {
      fieldValue = field.checked;
    } else {
      fieldValue = field.value.trim();
      field.value = fieldValue;
    }

    // If it's empty and not a field that we allow to be empty, restore to the default value
    if (!fieldValue && canBeEmptyFields.indexOf(fieldName) == -1) {
      bgSettings.clear(fieldName);
      fieldValue = bgSettings.get(fieldName);
    } else
      bgSettings.set(fieldName, fieldValue);

    $(fieldName).value = fieldValue;
    $(fieldName).setAttribute("savedValue", fieldValue);

    if (postSaveHooks[fieldName]) { postSaveHooks[fieldName](fieldValue); }
  }
  $("saveOptions").disabled = true;
}

// Restores select box state to saved value from localStorage.
function populateOptions() {
  for (var i = 0; i < editableFields.length; i++) {
    var val = bgSettings.get(editableFields[i]) || "";
    setFieldValue($(editableFields[i]), val);
  }
  onDataLoaded();
}

function restoreToDefaults() {
  for (var i = 0; i < editableFields.length; i++) {
    var val = bgSettings.defaults[editableFields[i]] || "";
    setFieldValue($(editableFields[i]), val);
  }
  onDataLoaded();
  enableSaveButton();
}

function setFieldValue(field, value) {
  if (field.getAttribute('type') == 'checkbox')
    field.checked = value;
  else {
    field.value = value;
    field.setAttribute("savedValue", value);
  }
}

function openAdvancedOptions(event) {
  var elements = document.getElementsByClassName("advancedOption");
  for (var i = 0; i < elements.length; i++)
    elements[i].style.display = (elements[i].style.display == "table-row") ? "none" : "table-row";
  event.preventDefault();
}
