
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
      this.query = [];

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
    getQueryString: function() {
      return this.query.join("")
    },
    find: function(query) {
      this.finder.find(query)
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
    this.initialized = true;
    this.finder = new BookmarkFinder({
      onResultsFound: function(bookmarks) {
        self.bookmarksFound = bookmarks;
        if(bookmarks.length>10) {
          bookmarks=bookmarks.slice(0, 10)
        }
        self.completionDialog.showCompletions(self.getQueryString(), bookmarks)
      }
    });

    this.completionDialog = new CompletionDialog({
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
        else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
          if (self.query.length == 0) {
            self.disable();
          } else {
            self.query.pop();
            self.finder.find(self.getQueryString())
          }
        } 
        else if(keyChar!=="up" && keyChar!=="down" && keyChar!=="left" && keyChar!="right") {
          self.query.push(keyChar);
          self.finder.find(self.getQueryString())
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

  var BookmarkFinder = function(config) {
    this.port = chrome.extension.connect({ name: "getBookmarks" })
    this.port.onMessage.addListener(function(msg) {
      (config.onResultsFound && config.onResultsFound(msg.bookmarks))
    })
  }
  BookmarkFinder.prototype = {
    find: function(query) {
      this.port.postMessage({query:query})
    }
  }

  //export global
  window.BookmarkMode = BookmarkMode;

}())
