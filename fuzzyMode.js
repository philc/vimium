var fuzzyMode = (function() {
  var fuzzyBox = null;  // the dialog instance for this window
  var completers = { };

  function getCompleter(name) {
    if (!(name in completers))
      completers[name] = new completion.BackgroundCompleter(name);
    return completers[name];
  }

  /** Trigger the fuzzy mode dialog */
  function start(name, reverseAction, refreshInterval) {
    var completer = getCompleter(name);
    if (!fuzzyBox)
      fuzzyBox = new FuzzyBox(10);
    completer.refresh();
    fuzzyBox.setCompleter(completer);
    fuzzyBox.setRefreshInterval(refreshInterval);
    fuzzyBox.show(reverseAction);
  }

  /** User interface for fuzzy completion */
  var FuzzyBox = function(maxResults) {
    this.prompt = '>';
    this.maxResults = maxResults;
    this.refreshInterval = 0;
    this.initDom();
  }
  FuzzyBox.prototype = {
    setCompleter: function(completer) {
      this.completer = completer;
      this.reset();
    },

    setRefreshInterval: function(refreshInterval) {
      this.refreshInterval = refreshInterval;
    },

    show: function(reverseAction) {
      this.reverseAction = reverseAction;
      this.box.style.display = 'block';
      this.input.focus();
      handlerStack.push({ keydown: this.onKeydown.bind(this) });
    },

    hide: function() {
      this.box.style.display = 'none';
      this.completionList.style.display = 'none';
      this.input.blur();
      handlerStack.pop();
    },

    reset: function() {
      this.input.value = '';
      this.updateTimer = null;
      this.completions = [];
      this.selection = 0;
      this.update(true);
    },

    updateSelection: function() {
      if (this.completions.length > 0)
        this.selection = Math.min(this.selection, this.completions.length - 1);
      for (var i = 0; i < this.completionList.children.length; ++i)
        this.completionList.children[i].className = (i == this.selection) ? 'selected' : '';
    },

    onKeydown: function(event) {
      var self = this;
      var keyChar = getKeyChar(event);

      if (isEscape(event)) {
        this.hide();
      }

      // move selection with Up/Down, Tab/Shift-Tab, Ctrl-k/Ctrl-j
      else if (keyChar === 'up' || (event.keyCode == 9 && event.shiftKey)
              || (keyChar === 'k' && event.ctrlKey)) {
        if (this.selection > 0)
          this.selection -= 1;
        this.updateSelection();
      }
      else if (keyChar === 'down' || (event.keyCode == 9 && !event.shiftKey)
              || (keyChar === 'j' && isPrimaryModifierKey(event))) {
        if (this.selection < this.completions.length - 1)
          this.selection += 1;
        this.updateSelection();
      }

      // refresh with F5
      else if (keyChar == 'f5') {
        this.completer.refresh();
        this.update(true); // force immediate update
      }

      // use primary action with Enter. Holding down Shift/Ctrl uses the alternative action
      // (opening in new tab)
      else if (event.keyCode == keyCodes.enter) {
        this.update(true, function() {
          var alternative = (event.shiftKey || isPrimaryModifierKey(event));
          if (self.reverseAction)
            alternative = !alternative;
          self.completions[self.selection].action[alternative ? 1 : 0]();
          self.hide();
        });
      }
      else {
        return true; // pass through
      }

      // it seems like we have to manually supress the event here and still return true...
      event.stopPropagation();
      event.preventDefault();
      return true;
    },

    updateCompletions: function(callback) {
      var self = this;
      query = this.input.value.replace(/^\s*/, '');

      this.completer.filter(query, this.maxResults, function(completions) {
        self.completions = completions;

        // update completion list with the new data
        self.completionList.innerHTML = completions.map(function(completion) {
          return '<li>' + completion.html + '</li>';
        }).join('');

        self.completionList.style.display = self.completions.length > 0 ? 'block' : 'none';
        self.updateSelection();
        if (callback) callback();
      });
    },

    update: function(force, callback) {
      force = force || false; // explicitely default to asynchronous updating

      if (force) {
        // cancel scheduled update
        if (this.updateTimer !== null)
          window.clearTimeout(this.updateTimer);
        this.updateCompletions(callback);
      } else if (this.updateTimer !== null) {
        // an update is already scheduled, don't do anything
        return;
      } else {
        var self = this;
        // always update asynchronously for better user experience and to take some load off the CPU
        // (not every keystroke will cause a dedicated update)
        this.updateTimer = setTimeout(function() {
          self.updateCompletions(callback);
          self.updateTimer = null;
        }, this.refreshInterval);
      }
    },

    initDom: function() {
      this.box = utils.createElementFromHtml(
        '<div id="fuzzybox" class="vimiumReset">'+
          '<div class="input">'+
            '<span class="prompt">' + utils.escapeHtml(this.prompt) + '</span> '+
            '<input type="text" class="query"></span></div>'+
          '<ul></ul></div>');
      this.box.style.display = 'none';
      document.body.appendChild(this.box);

      this.input = document.querySelector("#fuzzybox .query");
      this.input.addEventListener("input", function() { this.update(); }.bind(this));
      this.completionList = document.querySelector("#fuzzybox ul");
      this.completionList.style.display = 'none';
    },
  }

  // public interface
  return {
    activateAll:       function() { start('omni', false, 100); },
    activateAllNewTab: function() { start('omni', true,  100);  },
    activateTabs:      function() { start('tabs', false, 0);  },
  }

})();
