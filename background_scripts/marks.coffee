root = window.Marks = {}

marks = {}

root.create = (req, sender) ->
  marks[req.markName] =
    tabId: sender.tab.id
    scrollX: req.scrollX
    scrollY: req.scrollY

chrome.tabs.onUpdated.addListener (tabId, changeInfo, tab) ->
  if changeInfo.url?
    removeMarksForTab tabId

chrome.tabs.onRemoved.addListener (tabId, removeInfo) ->
  # XXX(jez): what about restored tabs?
  removeMarksForTab tabId

removeMarksForTab = (id) ->
  for markName, mark of marks
    if mark.tabId is id
      delete marks[markName]

root.goto = (req, sender) ->
  mark = marks[req.markName]
  chrome.tabs.update mark.tabId, selected: true
  chrome.tabs.sendMessage mark.tabId,
    name: "setScrollPosition"
    scrollX: mark.scrollX
    scrollY: mark.scrollY
  chrome.tabs.sendMessage mark.tabId,
    name: "showHUDforDuration",
    text: "Jumped to global mark '#{req.markName}'"
    duration: 1000
