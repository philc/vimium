var Clipboard = {
  _createTextArea: function() {
    var textArea = document.createElement("textarea");
    textArea.style.position = "absolute";
    textArea.style.left = "-100%";
    return textArea;
  },

  // http://groups.google.com/group/chromium-extensions/browse_thread/thread/49027e7f3b04f68/f6ab2457dee5bf55
  copy: function(data) {
    var textArea = this._createTextArea();
    textArea.value = data;

    document.body.appendChild(textArea);
    textArea.select();
    document.execCommand("Copy");
    document.body.removeChild(textArea);
  },

  paste: function() {
    var textArea = this._createTextArea();
    document.body.appendChild(textArea);
    textArea.focus();
    document.execCommand("Paste");
    var rv = textArea.value;
    document.body.removeChild(textArea);
    return rv;
  }
};
