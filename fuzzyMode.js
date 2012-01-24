var fuzzyMode = (function() {
  var fuzzyBox = null;  // the dialog instance for this window
  var completers = {};  // completer cache

  function createCompleter(name) {
    if (name === 'smart')
      return new completion.SmartCompleter({
        'wiki ': [ 'Wikipedia (en)', 'http://en.wikipedia.org/wiki/%s' ],
        'luck ': [ 'Google Lucky (en)', 'http://www.google.com/search?q=%s&btnI=I%27m+Feeling+Lucky' ],
        'cc '  : [ 'dict.cc',        'http://www.dict.cc/?s=%s' ],
        ';'    : [ 'goto',           '%s' ],
        '?'    : [ 'search',         function(query) { return utils.createSearchUrl(query) } ],
        });
    else if (name === 'history')
      return new completion.FuzzyHistoryCompleter(1500);
    else if (name === 'bookmarks')
      return new completion.FuzzyBookmarkCompleter();
    else if (name === 'tabs')
      return new completion.FuzzyTabCompleter();
    else if (name === 'tabsSorted')
      return new completion.MergingCompleter([getCompleter('tabs')]);
    else if (name === 'all')
      return new completion.MergingCompleter([
        getCompleter('smart'),
        getCompleter('bookmarks'),
        getCompleter('history'),
        getCompleter('tabs'),
        ]);
  }
  function getCompleter(name) {
    if (!(name in completers))
      completers[name] = createCompleter(name);
    return completers[name];
  }

  /** Trigger the fuzzy mode dialog */
  function start(name, reverseAction) {
    var completer = getCompleter(name);
    if (!fuzzyBox)
      fuzzyBox = new FuzzyBox(10, 300);
    completer.refresh();
    fuzzyBox.setCompleter(completer);
    fuzzyBox.show(reverseAction);
  }

  /** User interface for fuzzy completion */
  var FuzzyBox = function(maxResults, refreshInterval) {
    this.prompt = '>';
    this.maxResults = maxResults;
    this.refreshInterval = refreshInterval;
    this.initDom();
    this.reset();
  }
  FuzzyBox.prototype = {
    setCompleter: function(completer) {
      this.completer = completer;
      this.reset();
    },

    show: function(reverseAction) {
      this.reverseAction = reverseAction;
      this.box.style.display = 'block';
      var self = this;
      handlerStack.push({ keydown: function(event) { self.onKeydown(event); }});
    },

    hide: function() {
      this.box.style.display = 'none';
      handlerStack.pop();
    },

    reset: function() {
      this.query = '';
      // query used to filter the last completion result. We need this for asynchronous updating
      this.lastQuery = null;
      this.completions = [];
      this.selection = 0;
      // force synchronous updating so that the old results will not be flash up shortly
      this.update(true);
    },

    updateSelection: function() {
      for (var i = 0; i < this.completionList.children.length; ++i)
        this.completionList.children[i].className = (i == this.selection) ? 'selected' : '';
    },

    onKeydown: function(event) {
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

      else if (event.keyCode == keyCodes.backspace) {
        if (this.query.length > 0) {
          this.query = this.query.substr(0, this.query.length-1);
          this.update();
        }
      }

      // refresh with F5
      else if (keyChar == 'f5') {
        this.completer.refresh();
        this.update();
      }

      // use primary action with Enter. Holding down Shift/Ctrl uses the alternative action
      // (opening in new tab)
      else if (event.keyCode == keyCodes.enter) {
        this.update(true); // force synchronous update

        var alternative = (event.shiftKey || isPrimaryModifierKey(event));
        if (this.reverseAction)
          alternative = !alternative;
        this.completions[this.selection].action[alternative ? 1 : 0]();
        this.hide();
        this.reset();
      }

      else if (keyChar.length == 1) {
        this.query += keyChar;
        this.update();
      }

      event.stopPropagation();
      event.preventDefault();
      return true;
    },

    updateInput: function() {
      this.query = this.query.replace(/^\s*/, '');
      this.input.textContent = this.query;
    },

    updateCompletions: function() {
      if (this.query.length == 0) {
        this.completionList.style.display = 'none';
        return;
      }

      var self = this;
      this.completer.filter(this.query, function(completions) {
        self.completions = completions.slice(0, self.maxResults);

        // clear completions
        self.completionList.innerHTML = self.completions.map(function(completion) {
          return '<li>' + completion.render() + '</li>';
        }).join('');

        self.completionList.style.display = self.completions.length > 0 ? 'block' : 'none';
        self.updateSelection();
      });
    },

    update: function(sync) {
      sync = sync || false; // explicitely default to asynchronous updating
      this.updateInput();

      if (sync) {
        this.updateCompletions();
      } else {
        var self = this;
        // always update asynchronously for better user experience and to take some load off the CPU
        // (not every keystroke will cause a dedicated update)
        setTimeout(function() {
          if (self.query === self.lastQuery)
            return;
          self.lastQuery = self.query;
          self.updateCompletions();
        }, this.refreshInterval);
      }
    },

    initDom: function() {
      this.box = utils.createElementFromHtml(
        '<div id="fuzzybox" class="vimiumReset">'+
          '<div class="input">'+
            '<span id="fuzzyboxPrompt" class="prompt">' + utils.escapeHtml(this.prompt) + '</span> '+
            '<span id="fuzzyboxInput" class="query"></span></div>'+
          '<ul id="fuzzyboxCompletions"></ul></div>');
      this.box.style.display = 'none';
      document.body.appendChild(this.box);

      this.input          = document.getElementById("fuzzyboxInput");
      this.completionList = document.getElementById("fuzzyboxCompletions");
    },
  }

  // public interface
  return {
    activateAll:       function() { start('all',        false); },
    activateAllNewTab: function() { start('all',        true);  },
    activateTabs:      function() { start('tabsSorted', false); },
  }

})();
