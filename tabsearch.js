function searchTab() {
  TabSearchMode.enable();
}

// TODO: Avoid copy and paste from BookmarkMode here.

(function() {
  var TabSearchMode = {
    isEnabled: function() {
      return this.enabled;
    },
    enable: function() {
      this.enabled = true;

      if(!this.initialized) {
        initialize.call(this);
      }

      handlerStack.push({
        keydown: this.onKeydown,
        keyup: this.onKeyup
      });

      this.renderHUD();
      this.completionDialog.show();
    },
    disable: function() {
      this.enabled = false;
      this.completionDialog.hide();
      handlerStack.pop();
      HUD.hide();
    },
    renderHUD: function() {
      if (this.newTab)
        HUD.show("Switch to a tab");
    }
  }

  // private method
  var initialize = function() {
    var self = this;
    self.initialized = true;

    self.completionDialog = new CompletionDialog({
      source: findTabs,
      onSelect: function(selection) {
        chrome.extension.connect({ name: "selectTabById" }).postMessage({
          tabId: selection.id
        });
        self.disable();
      },
      renderOption: function(searchString, selection) {
        var displaytext = selection.title + " (" + selection.url + ")"

        if(displaytext.length>70) {
          displaytext = displaytext.substr(0, 70)+"...";
        }

        return displaytext.split(new RegExp(utils.quotemeta(searchString), "i"))
          .join("<strong>"+searchString+"</strong>")
      },
      initialSearchText: "Type a tab title or URL"
    })

    self.onKeydown = function(event) {
      var keyChar = getKeyChar(event);
      if (!keyChar)
        return;

      // TODO(philc): Ignore keys that have modifiers.
      if (isEscape(event)) {
        self.disable();
      }

      event.stopPropagation();
      event.preventDefault();
    };

    self.onKeyup = function(event) {
      event.stopPropagation();
      event.preventDefault();
    };
  }

  var findTabs = function(searchString, callback) {
    var port = chrome.extension.connect({ name: "getTabs" });
    port.onMessage.addListener(function(msg) {
      callback(msg.tabs);
      port = null;
    })
    port.postMessage({query:searchString});
  };

  //export global
  window.TabSearchMode = TabSearchMode;
}());
