# A list of the available commands, grouped by the headings they will appear under in the help dialog.
# Each command entry should provide the following options:
#   name:        The name of the command.
#   description: The description to appear beside the command in the help dialog.
#   context:     One of "frame", "background". Determines where the command is executed.
#                NOTE(mrmr1993): This is a string not a boolean to allow the addition of "all_frames" for
#                LinkHints in iframes etc. in the future.
#   repeat:      One of "normal", "pass_to_function", "none". Specifies how repetition of the command should
#                be handled
#   repeatLimit: [Optional] A number specifying the number of repeats beyond which we should prompt the user
#                to confirm that they REALLY want to repeat the command that many times. Mainly to shield the
#                user from tab creation/deletion commands. repeat must be one of "normal", "pass_to_function"
#                for this option to be valid.
#   advanced:    [Optional] A boolean specifying whether the command is advanced (and hence should be hidden
#                behind the "show advanced commands" toggle in the help dialog).
commandLists =
  pageScrolling: [
    {
      name: "scrollDown"
      description: "Scroll down"
      context: "frame"
      repeat: "normal"
    }
    {
      name: "scrollUp"
      description: "Scroll up"
      context: "frame"
      repeat: "normal"
    }
    {
      name: "scrollLeft"
      description: "Scroll left"
      context: "frame"
      repeat: "normal"
    }
    {
      name: "scrollRight"
      description: "Scroll right"
      context: "frame"
      repeat: "normal"
    }
    {
      name: "scrollToTop"
      description: "Scroll to the top of the page"
      context: "frame"
      repeat: "none"
    }
    {
      name: "scrollToBottom"
      description: "Scroll to the bottom of the page"
      context: "frame"
      repeat: "none"
    }
    {
      name: "scrollToLeft"
      description: "Scroll all the way to the left"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "scrollToRight"
      description: "Scroll all the way to the right"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "scrollPageDown"
      description: "Scroll a page down"
      context: "frame"
      repeat: "normal"
    }
    {
      name: "scrollPageUp"
      description: "Scroll a page up"
      context: "frame"
      repeat: "normal"
    }
    {
      name: "scrollFullPageUp"
      description: "Scroll a full page up"
      context: "frame"
      repeat: "normal"
    }
    {
      name: "scrollFullPageDown"
      description: "Scroll a full page down"
      context: "frame"
      repeat: "normal"
    }
  ]
  pageNavigation: [
    {
      name: "toggleViewSource"
      description: "View page source"
      context: "frame"
      repeat: "none"
    }
    {
      name: "goPrevious"
      description: "Follow the link labeled previous or <"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "goNext"
      description: "Follow the link labeled next or >"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "nextFrame"
      description: "Cycle forward to the next frame on the page"
      context: "frame"
      repeat: "pass_to_function"
    }
    {
      name: "Marks.activateCreateMode"
      description: "Create a new mark"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "Marks.activateGotoMode"
      description: "Go to a mark"
      context: "frame"
      repeat: "none"
      advanced: true
    }
  ]
  urlManipulation: [
    {
      name: "copyCurrentUrl"
      description: "Copy the current URL to the clipboard"
      context: "frame"
      repeat: "none"
    }
    {
      name: "openCopiedUrlInCurrentTab"
      description: "Open the clipboard's URL in the current tab"
      context: "background"
      repeat: "normal"
      repeatLimit: 20
    }
    {
      name: "openCopiedUrlInNewTab"
      description: "Open the clipboard's URL in a new tab"
      context: "background"
      repeat: "normal"
    }
    {
      name: "goUp"
      description: "Go up the URL hierarchy"
      context: "frame"
      repeat: "pass_to_function"
      advanced: true
    }
    {
      name: "goToRoot"
      description: "Go to root of current URL hierarchy"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "Vomnibar.activateEditUrl"
      description: "Edit the current URL"
      context: "frame"
      repeat: "none"
    }
    {
      name: "Vomnibar.activateEditUrlInNewTab"
      description: "Edit the current URL and open in a new tab"
      context: "frame"
      repeat: "none"
    }
  ]
  insertMode: [
    {
      name: "enterInsertMode"
      description: "Enter insert mode"
      context: "frame"
      repeat: "none"
    }
    {
      name: "focusInput"
      description: "Focus the first text box on the page. Cycle between them using tab"
      context: "frame"
      repeat: "pass_to_function"
      advanced: true
    }
  ]
  linkHints: [
    {
      name: "LinkHints.activateMode"
      description: "Open a link in the current tab"
      context: "frame"
      repeat: "none"
    }
    {
      name: "LinkHints.activateModeToOpenInNewTab"
      description: "Open a link in a new tab"
      context: "frame"
      repeat: "none"
    }
    {
      name: "LinkHints.activateModeToOpenInNewForegroundTab"
      description: "Open a link in a new tab & switch to it"
      context: "frame"
      repeat: "none"
    }
    {
      name: "LinkHints.activateModeWithQueue"
      description: "Open multiple links in a new tab"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "LinkHints.activateModeToCopyLinkUrl"
      description: "Copy a link URL to the clipboard"
      context: "frame"
      repeat: "none"
    }
    {
      name: "LinkHints.activateModeToDownloadLink"
      description: "Download link url"
      context: "frame"
      repeat: "none"
      advanced: true
    }
    {
      name: "LinkHints.activateModeToOpenIncognito"
      description: "Open a link in incognito window"
      context: "frame"
      repeat: "none"
      advanced: true
    }
  ]
  vomnibar: [
    {
      name: "Vomnibar.activate"
      description: "Open URL, bookmark, or history entry"
      context: "frame"
      repeat: "none"
    }
    {
      name: "Vomnibar.activateInNewTab"
      description: "Open URL, bookmark, history entry, in a new tab"
      context: "frame"
      repeat: "none"
    }
    {
      name: "Vomnibar.activateBookmarks"
      description: "Open a bookmark"
      context: "frame"
      repeat: "none"
    }
    {
      name: "Vomnibar.activateBookmarksInNewTab"
      description: "Open a bookmark in a new tab"
      context: "frame"
      repeat: "none"
    }
  ]
  findCommands: [
    {
      name: "enterFindMode"
      description: "Enter find mode"
      context: "frame"
      repeat: "none"
    }
    {
      name: "performFind"
      description: "Cycle forward to the next find match"
      context: "frame"
      repeat: "pass_to_function"
    }
    {
      name: "performBackwardsFind"
      description: "Cycle backward to the previous find match"
      context: "frame"
      repeat: "pass_to_function"
    }
  ]
  historyNavigation: [
    {
      name: "reload"
      description: "Reload the page"
      context: "frame"
      repeat: "none"
    }
    {
      name: "goBack"
      description: "Go back in history"
      context: "frame"
      repeat: "pass_to_function"
    }
    {
      name: "goForward"
      description: "Go forward in history"
      context: "frame"
      repeat: "pass_to_function"
    }
  ]
  tabManipulation: [
    {
      name: "nextTab"
      description: "Go one tab right"
      context: "background"
      repeat: "normal"
    }
    {
      name: "previousTab"
      description: "Go one tab left"
      context: "background"
      repeat: "normal"
    }
    {
      name: "firstTab"
      description: "Go to the first tab"
      context: "background"
      repeat: "normal"
    }
    {
      name: "lastTab"
      description: "Go to the last tab"
      context: "background"
      repeat: "normal"
    }
    {
      name: "Vomnibar.activateTabSelection"
      description: "Search through your open tabs"
      context: "frame"
      repeat: "none"
    }
    {
      name: "createTab"
      description: "Create new tab"
      context: "background"
      repeat: "normal"
      repeatLimit: 20
    }
    {
      name: "duplicateTab"
      description: "Duplicate current tab"
      context: "background"
      repeat: "normal"
      repeatLimit: 20
    }
    {
      name: "removeTab"
      description: "Close current tab"
      context: "background"
      repeat: "normal"
      # Require confirmation to remove more tabs than we can restore.
      repeatLimit: (if chrome.session then chrome.session.MAX_SESSION_RESULTS else 25)
    }
    {
      name: "restoreTab"
      description: "Restore closed tab"
      context: "background"
      repeat: "normal"
      repeatLimit: (if chrome.session then chrome.session.MAX_SESSION_RESULTS else 25)
    }
    {
      name: "moveTabToNewWindow"
      description: "Move tab to new window"
      context: "background"
      repeat: "normal"
      advanced: true
    }
    {
      name: "togglePinTab"
      description: "Pin/unpin current tab"
      context: "background"
      repeat: "normal"
    }
    {
      name: "closeTabsOnLeft"
      description: "Close tabs on the left"
      context: "background"
      repeat: "none"
      advanced: true
    }
    {
      name: "closeTabsOnRight"
      description: "Close tabs on the right"
      context: "background"
      repeat: "none"
      advanced: true
    }
    {
      name: "closeOtherTabs"
      description: "Close all other tabs"
      context: "background"
      repeat: "none"
      advanced: true
    }
    {
      name: "moveTabLeft"
      description: "Move tab to the left"
      context: "background"
      repeat: "pass_to_function"
      advanced: true
    }
    {
      name: "moveTabRight"
      description: "Move tab to the right"
      context: "background"
      repeat: "pass_to_function"
      advanced: true
    }
  ]
  misc: [
    {
      name: "showHelp"
      description: "Show help"
      context: "background"
      repeat: "normal"
    }
  ]

groupDescriptions =
  pageScrolling: "Scrolling the page"
  pageNavigation: "Navigating the page"
  urlManipulation: "Manipulating URLs"
  insertMode: "Insert mode"
  linkHints: "Working with links"
  vomnibar: "Navigate to a page"
  findCommands: "Using find"
  historyNavigation: "Navigating history"
  tabManipulation: "Manipulating tabs"
  misc: "Miscellaneous"

root = exports ? window
root.commandLists = commandLists
root.groupDescriptions = groupDescriptions
