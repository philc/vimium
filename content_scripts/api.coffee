activateVomnibar = () ->
  root = exports ? (window.root ?= {})
  root.Vomnibar.activate(root.sourceFrameId, {options : {}})
  return

exportFunction(activateVomnibar, window, {defineAs:'activateVomnibar'})
