var fuzzyMode = (function() {
  /** Trigger the fuzzy mode dialog */
  var fuzzyBox = null;
  function start(newTab) {
    if (!fuzzyBox) {
      var completer = new completion.MergingCompleter([
        new completion.SmartCompleter({
          'wiki ': [ 'Wikipedia (en)', 'http://en.wikipedia.org/wiki/%s' ],
          'cc '  : [ 'dict.cc',        'http://www.dict.cc/?s=%s' ],
          ';'    : [ 'goto',           '%s' ],
          '?'    : [ 'search',         function(query) { return utils.createSearchUrl(query) } ],
        }),
        new completion.FuzzyHistoryCompleter(1000),
        new completion.FuzzyBookmarkCompleter(),
      ]);
      completer.refresh();
      fuzzyBox = new FuzzyBox(completer, 10);
    }
    fuzzyBox.show(newTab);
  }

  /** User interface for fuzzy completion */
  var FuzzyBox = function(completer, maxResults) {
    this.prompt = '> ';
    this.maxResults = maxResults || 10;
    this.completer = completer;
    this.initDom();
    this.reset();
  }
  FuzzyBox.prototype = {
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
      this.completions = [];
      this.selection = 0;
      this.update();
    },

    updateSelection: function() {
      var items = this.completionList.childNodes;
      for (var i = 0; i < items.length; ++i) {
        items[i].className = (i == this.selection) ? 'selected' : '';
      }
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

    update: function() {
      this.query = this.query.replace(/^\s*/, '');
      this.input.textContent = this.query;

      if (this.query.length == 0) {
        this.completionList.style.display = 'none';
        return;
      }
      this.completionList.style.display = 'block';

      var self = this;
      this.completer.filter(this.query, function(completions) {
        // clear completions
        self.completions = [];
        while (self.completionList.hasChildNodes())
          self.completionList.removeChild(self.completionList.firstChild);

        for (var i = 0; i < completions.length && i < self.maxResults; ++i) {
          self.completions.push(completions[i]);
          var li = document.createElement('li');
          li.innerHTML = completions[i].render();
          self.completionList.appendChild(li);
        }
        self.updateSelection();
      });
    },

    initDom: function() {
      this.box = document.createElement('div');
      this.box.id = 'fuzzybox';
      this.box.className = 'vimiumReset';

      var inputBox = document.createElement('div');
      inputBox.className = 'input';

      var promptSpan = document.createElement('span');
      promptSpan.className = 'prompt';
      promptSpan.textContent = this.prompt;

      this.input = document.createElement('span');
      this.input.className = 'query';

      inputBox.appendChild(promptSpan);
      inputBox.appendChild(this.input);

      this.completionList = document.createElement('ul');

      this.box.appendChild(inputBox);
      this.box.appendChild(this.completionList);

      this.hide();
      document.body.appendChild(this.box);
    },
  }

  // public interface
  return {
    activate:       function() { start(false); },
    activateNewTab: function() { start(true);  },
  }

})();
