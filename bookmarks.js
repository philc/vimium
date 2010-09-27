
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
      
      this.keyPressListener.enable();
    },
    disable: function() {
      this.enabled = false;
      this.keyPressListener.disable();
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
    this.initialized = true;
    this.finder = new BookmarkFinder({
      onResultsFound: function(bookmarks) {
        BookmarkMode.bookmarksFound = bookmarks;
        for(var i=0;i<bookmarks.length;i++) { 
          console.log(bookmarks[i].title)
        }
      }
    });

    this.keyPressListener = new KeyPressListener({
      keyDown: function(key) {
        // shift key will toggle between new tab/same tab
        if (event.keyCode == keyCodes.shiftKey) {
          BookmarkMode.invertNewTabSetting();
          shiftWasPressedWhileToggled = true
          return
        }

        if(event.keyCode == keyCodes.enter) {
          var bookmarksFound = BookmarkMode.bookmarksFound;
          if(bookmarksFound && bookmarksFound.length>0) {
            var url = bookmarksFound[0].url
            if(BookmarkMode.newTab)
              window.open(url)
            else window.location=url
          }
        }

        var keyChar = getKeyChar(event);
        if (!keyChar)
          return;

        // TODO(philc): Ignore keys that have modifiers.
        if (isEscape(event)) {
          BookmarkMode.disable();
        } 
        else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
          if (BookmarkMode.query.length == 0) {
            BookmarkMode.disable();
          } else {
            BookmarkMode.query.pop();
          }
        } 
        else {
          BookmarkMode.query.push(keyChar);
        } 

        BookmarkMode.finder.find(BookmarkMode.getQueryString())
      },
      keyUp: function(event) {
        // shift key will toggle between new tab/same tab
        if (event.keyCode == keyCodes.shiftKey && shiftWasPressedWhileToggled) {
          BookmarkMode.invertNewTabSetting();
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
      console.log("You typed: " + query)
      this.port.postMessage({query:query})
    }
  }

  var KeyPressListener = function(handlers) {
    this.handlers = handlers; 
  }

  KeyPressListener.prototype = {
    enable: function() {
      var handlers = this.handlers;
      (handlers.keyDown && document.addEventListener("keydown", handlers.keyDown, true));
      (handlers.keyUp && document.addEventListener("keyup", handlers.keyUp, true));
    },
    disable: function() {
      var handlers = this.handlers;
      (handlers.keyDown && document.removeEventListener("keydown", handlers.keyDown, true));
      (handlers.keyUp && document.removeEventListener("keyup", handlers.keyUp, true));
    }
  }

  //export global
  window.BookmarkMode = BookmarkMode;

}())
