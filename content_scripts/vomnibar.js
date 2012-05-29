var vomnibar = (function() {
  var vomnibarUI = null;  // the dialog instance for this window
  var completers = { };

  function getCompleter(name) {
    if (!(name in completers))
      completers[name] = new BackgroundCompleter(name);
    return completers[name];
  }

  /*
   * Activate the Vomnibox.
   */
  function activate(completerName, refreshInterval, initialQueryValue) {
    var completer = getCompleter(completerName);
    if (!vomnibarUI)
      vomnibarUI = new VomnibarUI();
    completer.refresh();
    vomnibarUI.setCompleter(completer);
    vomnibarUI.setRefreshInterval(refreshInterval);
    if (initialQueryValue)
      vomnibarUI.setQuery(initialQueryValue);
    vomnibarUI.show();
    return vomnibarUI;
  }

  /** User interface for fuzzy completion */
  var VomnibarUI = Class.extend({
    init: function() {
      this.prompt = '>';
      this.refreshInterval = 0;
      this.initDom();
    },

    setQuery: function(query) { this.input.value = query; },

    setCompleter: function(completer) {
      this.completer = completer;
      this.reset();
    },

    setRefreshInterval: function(refreshInterval) { this.refreshInterval = refreshInterval; },

    show: function() {
      this.box.style.display = "block";
      this.input.focus();
      handlerStack.push({ keydown: this.onKeydown.bind(this) });
    },

    hide: function() {
      this.box.style.display = "none";
      this.completionList.style.display = "none";
      this.input.blur();
      handlerStack.pop();
    },

    reset: function() {
      this.input.value = "";
      this.updateTimer = null;
      this.completions = [];
      this.selection = 0;
      this.update(true);
    },

    updateSelection: function() {
      if (this.completions.length > 0)
        this.selection = Math.min(this.selection, this.completions.length - 1);
      for (var i = 0; i < this.completionList.children.length; ++i)
        this.completionList.children[i].className = (i == this.selection) ? "selected" : "";
    },

    /*
     * Returns the user's action ("up", "down", "enter", "dismiss" or null) based on their keypress.
     * We support the arrow keys and other shortcuts for moving, so this method hides that complexity.
     */
    actionFromKeyEvent: function(event) {
      var key = getKeyChar(event);
      if (isEscape(event))
        return "dismiss";
      else if (key == "up" ||
          (event.shiftKey && event.keyCode == keyCodes.tab) ||
          (event.ctrlKey && (key == "k" || key == "p")))
        return "up";
      else if (key == "down" ||
        (event.keyCode == keyCodes.tab && !event.shiftKey) ||
        (event.ctrlKey && (key == "j" || key == "n")))
        return "down";
      else if (event.keyCode == keyCodes.enter)
        return "enter";
    },

    onKeydown: function(event) {
      var action = this.actionFromKeyEvent(event);
      if (!action) return true; // pass through

      if (action == "dismiss") {
        this.hide();
      }
      else if (action == "up") {
        if (this.selection > 0)
          this.selection -= 1;
        this.updateSelection();
      }
      else if (action == "down") {
        if (this.selection < this.completions.length - 1)
          this.selection += 1;
        this.updateSelection();
      }
      else if (action == "enter") {
        this.update(true, function() {
          // Shift+Enter will open the result in a new tab instead of the current tab.
          var openInNewTab = (event.shiftKey || isPrimaryModifierKey(event));
          this.completions[this.selection].performAction(openInNewTab);
          this.hide();
        }.proxy(this));
      }

      // It seems like we have to manually supress the event here and still return true.
      event.stopPropagation();
      event.preventDefault();
      return true;
    },

    updateCompletions: function(callback) {
      query = this.input.value.replace(/^\s*/, "");

      this.completer.filter(query, function(completions) {
        this.completions = completions;
        this.populateUiWithCompletions(completions);
        if (callback) callback();
      }.proxy(this));
    },

    populateUiWithCompletions: function(completions) {
      // update completion list with the new data
      this.completionList.innerHTML = completions.map(function(completion) {
        return "<li>" + completion.html + "</li>";
      }).join('');

      this.completionList.style.display = (completions.length > 0) ? "block" : "none";
      this.updateSelection();
    },

    update: function(updateSynchronously, callback) {
      if (updateSynchronously) {
        // cancel scheduled update
        if (this.updateTimer !== null)
          window.clearTimeout(this.updateTimer);
        this.updateCompletions(callback);
      } else if (this.updateTimer !== null) {
        // an update is already scheduled, don't do anything
        return;
      } else {
        // always update asynchronously for better user experience and to take some load off the CPU
        // (not every keystroke will cause a dedicated update)
        this.updateTimer = setTimeout(function() {
          this.updateCompletions(callback);
          this.updateTimer = null;
        }.proxy(this), this.refreshInterval);
      }
    },

    initDom: function() {
      this.box = utils.createElementFromHtml(
        '<div id="vomnibar" class="vimiumReset">' +
          '<div class="searchArea">' +
            '<input type="text" />' +
          '</div>' +
          '<ul></ul>' +
        '</div>');
      this.box.style.display = 'none';
      document.body.appendChild(this.box);

      this.input = document.querySelector("#vomnibar input");
      this.input.addEventListener("input", function() { this.update(); }.bind(this));
      this.completionList = document.querySelector("#vomnibar ul");
      this.completionList.style.display = "none";
    }
  });

  /*
   * Sends filter and refresh requests to a Vomnibox completer on the background page.
   */
  var BackgroundCompleter = Class.extend({
    /* - name: The background page completer that you want to interface with. Either "omni" or "tabs". */
    init: function(name) {
      this.name = name;
      this.filterPort = chrome.extension.connect({ name: "filterCompleter" });
    },

    refresh: function() { chrome.extension.sendRequest({ handler: "refreshCompleter", name: this.name }); },

    filter: function(query, callback) {
      var id = utils.createUniqueId();
      this.filterPort.onMessage.addListener(function(msg) {
        if (msg.id != id) return;
        // The result objects coming from the background page will be of the form:
        //   { html: "", action: "", url: "" }
        // action will be either "navigateToUrl" or "switchToTab".
        var results = msg.results.map(function(result) {
          var functionToCall = completionActions[result.action];
          if (result.action == "navigateToUrl")
            functionToCall = functionToCall.curry(result.url);
          else if (result.action == "switchToTab")
            functionToCall = functionToCall.curry(result.tabId);
          result.performAction = functionToCall;
          return result;
        });
        callback(results);
      });
      this.filterPort.postMessage({ id: id, name: this.name, query: query });
    }
  });

  /*
   * These are the actions we can perform when the user selects a result in the Vomnibox.
   */
  var completionActions = {
    navigateToUrl: function(url, openInNewTab) {
      // If the URL is a bookmarklet prefixed with javascript:, we shouldn't open that in a new tab.
      if (url.indexOf("javascript:") == 0)
        openInNewTab = false;
      chrome.extension.sendRequest({
        handler: openInNewTab ? "openUrlInNewTab" : "openUrlInCurrentTab",
        url: url,
        selected: openInNewTab
      });
    },

    switchToTab: function(tabId) {
      chrome.extension.sendRequest({ handler: "selectSpecificTab", id: tabId });
    }
  };

  // public interface
  return {
    activate: function() { activate("omni", 100); },
    activateWithCurrentUrl: function() { activate("omni", 100, window.location.toString()); },
    activateTabSelection: function() { activate("tabs", 0); },
    /* Used by our vomnibar dev harness. */
    getUI: function() { return vomnibarUI; }
  }
})();
