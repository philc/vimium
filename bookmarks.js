
function activateBookmarkFindModeToOpenInNewTab() { 
  BookmarkMode.openInNewTab(true)
  BookmarkMode.enable()
}

function activateBookmarkFindMode() {
  BookmarkMode.openInNewTab(false)
  BookmarkMode.enable()
}

(function() {
  // so when they let go of shift after hitting capital "B" it won't
  // untoggle it
  var shiftWasPressedWhileToggled = false;

  var BookmarkMode = {
    isEnabled: function() {
      return this.enabled
    },
    openInNewTab: function(newTab) {
      this.newTab = newTab
    },
    invertNewTabSetting: function() {
      this.newTab = !this.newTab;
      if(this.isEnabled()) {
        this.renderHUD()
      }
    },
    enable: function() {
      this.enabled = true;

      if(!this.initialized) {
        initialize.call(this)
      }
      
      this.renderHUD();
      this.completionDialog.show();
      
      this.keyPressListener.enable();
    },
    disable: function() {
      this.enabled = false;
      this.keyPressListener.disable();
      this.completionDialog.hide()
      HUD.hide();
    },
    renderHUD: function() {
      if (this.newTab)
        HUD.show("Open bookmark in new tab");
      else
        HUD.show("Open bookmark in current tab");
    }
    
  }

  // private method
  var initialize = function() {
    var self = this;
    self.initialized = true;

    self.completionDialog = new CompletionDialog({
      source: findBookmarks,
      onSelect: function(selection) {
        var url = selection.url
        var isABookmarklet = function(url) {
          return url.indexOf("javascript:")===0
        }

        if(!self.newTab || isABookmarklet(url)) {
          window.location=url
        }
        else {
          window.open(url)
        }
        
        self.disable();
      },
      renderOption: function(searchString, selection) {

        var displaytext = selection.title + " (" + selection.url + ")"

        if(displaytext.length>70) {
          displaytext = displaytext.substr(0, 70)+"..."
        }

        return displaytext.split(new RegExp(searchString, "i")).join("<strong>"+searchString+"</strong>")
      },
      initialSearchText: "Type a bookmark name or URL"
    })

    this.keyPressListener = new KeyPressListener({
      keyDown: function(event) {
        // shift key will toggle between new tab/same tab
        if (event.keyCode == keyCodes.shiftKey) {
          self.invertNewTabSetting();
          shiftWasPressedWhileToggled = true
          return
        }

        var keyChar = getKeyChar(event);
        if (!keyChar)
          return;

        // TODO(philc): Ignore keys that have modifiers.
        if (isEscape(event)) {
          self.disable();
        } 

        event.stopPropagation();
        event.preventDefault();
      },
      keyUp: function(event) {
        // shift key will toggle between new tab/same tab
        if (event.keyCode == keyCodes.shiftKey && shiftWasPressedWhileToggled) {
          self.invertNewTabSetting();
          shiftWasPressedWhileToggled = false
        }
        event.stopPropagation();
        event.preventDefault();
      }
    })
  }

  var findBookmarks = function(searchString, callback) {
    var port = chrome.extension.connect({ name: "getBookmarks" }) 
    port.onMessage.addListener(function(msg) {
      callback(msg.bookmarks)
      port = null
    })
    port.postMessage({query:searchString})
  };

  //export global
  window.BookmarkMode = BookmarkMode;

}())
