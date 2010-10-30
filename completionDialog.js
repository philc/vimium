(function(window, document) {

  var CompletionDialog = function(options) {
    this.options = options
  }

  CompletionDialog.prototype = {
    show: function() {
      this.showCompletions()
    },
    showCompletions: function(searchString, completions) {
      this.searchString = searchString;
      this.completions = completions;
      if(!this.initialized) {
        initialize.call(this);
        this.initialized=true;
      }
      var container = this.getDisplayElement()
      clearChildren(container);

      if(searchString===undefined) {
        this.container.className = "dialog";
        createDivInside(container).innerHTML=this.options.initialSearchText || "Begin typing"
      }
      else {
        this.container.className = "dialog completions";
        var searchBar = createDivInside(container)
        searchBar.innerHTML=searchString
        searchBar.className="searchBar"

        searchResults = createDivInside(container)
        searchResults.className="searchResults"
        if(completions.length<=0) {
          var resultDiv = createDivInside(searchResults)
          resultDiv.className="noResults"
          resultDiv.innerHTML="No results found"
        }
        else {
          for(var i=0;i<completions.length;i++) {
            var resultDiv = createDivInside(searchResults)
            if(i===this.currentSelection) {
              resultDiv.className="selected"
            }
            resultDiv.innerHTML=this.options.renderOption(searchString, completions[i])
          }
        }
      }

      container.style.top=(window.innerHeight/2-container.clientHeight/2) + "px";
      container.style.left=(window.innerWidth/2-container.clientWidth/2) + "px";
      if(!this.isShown) {
        this.keyPressListener.enable();
        clearInterval(this._tweenId);
        this._tweenId = Tween.fade(container, 1.0, 150);
        this.isShown=true;
      }
    },
    hide: function() {
      if(this.isShown) {
        this.keyPressListener.disable();
        this.isShown=false;
        this.currentSelection=0;
        clearInterval(this._tweenId);
        this._tweenId = Tween.fade(this.container, 0, 150);
      }
    },
    getDisplayElement: function() {
      if(!this.container) {
        this.container = createDivInside(document.body)
      }
      return this.container
    }
  }

  var initialize = function() {
    addCssToPage(completionCSS)
    
    this.currentSelection=0;
    var self = this;
    this.keyPressListener = new KeyPressListener({
      keyDown: function(event) {
        var keyChar = getKeyChar(event);
        if(keyChar==="up") {
          if(self.currentSelection>0) {
            self.currentSelection-=1;
          }
          self.showCompletions(self.searchString, self.completions) 
        }
        else if(keyChar==="down") {
          if(self.currentSelection<self.completions.length-1) {
            self.currentSelection+=1;
          }
          self.showCompletions(self.searchString, self.completions) 
        }
        else if(event.keyCode == keyCodes.enter) {
          self.options.onSelect(self.completions[self.currentSelection])
        }
        
        event.stopPropagation();
        event.preventDefault();
      }
    })
  }

  var createDivInside = function(parent) {
    var element = document.createElement("div");
    parent.appendChild(element);
    return element
  }
  
  var clearChildren = function(elem) {
    if (elem.hasChildNodes()) {
      while (elem.childNodes.length >= 1) {
        elem.removeChild(elem.firstChild);       
      } 
    }
  }
  
  var completionCSS = ".dialog {"+
    "position:fixed;"+
    "background-color: #ebebeb;" +
    "z-index: 99999998;" +
    "border: 1px solid #b3b3b3;" +
    "font-size: 12px;" +
    "text-align:left;"+
    "color: black;" +
    "padding:10px;"+
    "border-radius: 4px;" +
    "font-family: Lucida Grande, Arial, Sans;" +
    "}"+
    ".completions {"+
    "width:400px;"+
    "}"+
    ".completions .searchBar {"+
    "height: 15px;"+
    "border-bottom: 1px solid #b3b3b3;"+
    "}"+
    ".completions .searchResults {"+
    "}"+
    ".completions .searchResults .selected{"+
    "background-color:#aaa;"+
    "border-radius: 4px;" +
    "}"+
    ".completions div{"+
    "padding:4px;"+
    "}"+
    ".completions div strong{"+
    "color: black;" +
    "font-weight:bold;"+
    "}"+
    ".completions .noResults{"+
    "color:#555;"+
    "}";

  window.CompletionDialog = CompletionDialog;

}(window, document))
