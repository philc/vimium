root = window.Marks = {}

marks = {}

root.create = (req, sender) ->
  marks[req.markName] =
    tabId: sender.tab.id
    scrollX: req.scrollX
    scrollY: req.scrollY

chrome.tabs.onUpdated.addListener (tabId, changeInfo, tab) ->
  removeMarksForTab tabId if changeInfo.url?

chrome.tabs.onRemoved.addListener (tabId, removeInfo) ->
  # XXX(jez): what about restored tabs?
  removeMarksForTab tabId

removeMarksForTab = (id) ->
  (delete marks[markName] if mark.tabId is id) for markName, mark of marks

root.goto = (req, sender) ->
  mark = marks[req.markName]
  chrome.tabs.update mark.tabId, selected: true
  chrome.tabs.sendRequest mark.tabId,
    name: "setScrollPosition"
    scrollX: mark.scrollX
    scrollY: mark.scrollY
  chrome.tabs.sendRequest mark.tabId,
    name: "showHUDforDuration",
    text: "Jumped to global mark '#{req.markName}'"
    duration: 1000
