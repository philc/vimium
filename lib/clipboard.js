const Clipboard = {
  _createTextArea(tagName) {
    if (tagName == null) { tagName = "textarea"; }
    const textArea = document.createElement(tagName);
    textArea.style.position = "absolute";
    textArea.style.left = "-100%";
    textArea.contentEditable = "true";
    return textArea;
  },

  // http://groups.google.com/group/chromium-extensions/browse_thread/thread/49027e7f3b04f68/f6ab2457dee5bf55
  async copy({data}) {
    const textArea = this._createTextArea();
    textArea.value = data.replace(/\xa0/g, " ");

    document.body.appendChild(textArea);
    textArea.select();
    await navigator.clipboard.writeText(textArea.value);
    document.body.removeChild(textArea);
  },

  // Returns a string representing the clipboard contents. Supports rich text clipboard values.
  async paste() {
    const textArea = this._createTextArea("div"); // Use a <div> so Firefox pastes rich text.
    document.body.appendChild(textArea);
    textArea.focus();
    const value = await navigator.clipboard.readText();
    document.body.removeChild(textArea);
    // When copying &nbsp; characters, they get converted to \xa0. Convert to space instead. See #2217.
    return value.replace(/\xa0/g, " ");
  }
};


window.Clipboard = Clipboard;
