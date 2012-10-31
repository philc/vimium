onLoad = ->
  document.getElementById("optionsLink").setAttribute "href", chrome.extension.getURL("pages/options.html")
  chrome.tabs.getSelected null, (tab) ->
    # The common use case is to disable Vimium at the domain level.
    # This regexp will match "http://www.example.com/" from "http://www.example.com/path/to/page.html".
    domain = tab.url.match(/[^\/]*\/\/[^\/]*\//) or tab.url
    document.getElementById("popupInput").value = domain + "*"

onExcludeUrl = (e) ->
  url = document.getElementById("popupInput").value
  chrome.extension.getBackgroundPage().addExcludedUrl url
  document.getElementById("excludeConfirm").setAttribute "style", "display: inline-block"

document.addEventListener "DOMContentLoaded", ->
  document.getElementById("popupButton").addEventListener "click", onExcludeUrl, false
  onLoad()
