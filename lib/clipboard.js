var Clipboard = {
  // http://groups.google.com/group/chromium-extensions/browse_thread/thread/49027e7f3b04f68/f6ab2457dee5bf55
  copy: function(data) {
          var textArea = document.createElement("textarea");
          textArea.style.position = "absolute";
          textArea.style.left = "-100%";
          textArea.value = data;

          document.body.appendChild(textArea);
          textArea.select();
          document.execCommand("Copy");
          document.body.removeChild(textArea);
        }
};
