Clipboard =
  _createTextArea: ->
    textArea = document.createElement("textarea")
    textArea.style.position = "absolute"
    textArea.style.left = "-100%"
    textArea

  # http://groups.google.com/group/chromium-extensions/browse_thread/thread/49027e7f3b04f68/f6ab2457dee5bf55
  copy: (data) ->
    textArea = @_createTextArea()
    textArea.value = data

    document.body.appendChild(textArea)
    textArea.select()
    document.execCommand("Copy")
    document.body.removeChild(textArea)

  paste: ->
    textArea = @._createTextArea()
    document.body.appendChild(textArea)
    textArea.focus()
    document.execCommand("Paste")
    value = textArea.value
    document.body.removeChild(textArea)
    value


root = exports ? window
root.Clipboard = Clipboard
