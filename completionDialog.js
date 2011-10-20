(function(window, document) {

  var CompletionDialog = function(options) {
    this.options = options;
  }

  CompletionDialog.prototype = {
    show: function() {
      if(!this.isShown) {
        this.isShown=true;
        this.query = [];
        if(!this.initialized) {
          initialize.call(this);
          this.initialized=true;
        }
        handlerStack.push({ keydown: this.onKeydown });
        render.call(this);
        clearInterval(this._tweenId);
        this._tweenId = Tween.fade(this.container, 1.0, 150);
      }
    },
    hide: function() {
      if(this.isShown) {
        handlerStack.pop();
        this.isShown=false;
        this.currentSelection=0;
        clearInterval(this._tweenId);
        this._tweenId = Tween.fade(this.container, 0, 150);
      }
    },
    getDisplayElement: function() {
      if(!this.container) {
        this.container = createDivInside(document.body);
      }
      return this.container;
    },
    getQueryString: function() {
      return this.query.join("");
    }
  }

  var initialize = function() {
    var self = this;
    addCssToPage(completionCSS);
    
    self.currentSelection=0;

    self.onKeydown = function(event) {
      var keyChar = getKeyChar(event);
      // change selection with up or Shift-Tab
      if(keyChar==="up" || (event.keyCode == 9 && event.shiftKey)) {
        if(self.currentSelection>0) {
          self.currentSelection-=1;
        }
        render.call(self,self.getQueryString(), self.completions);
      }
      // change selection with down or Tab
      else if(keyChar==="down" || (event.keyCode == 9 && !event.shiftKey)) {
        if(self.currentSelection<self.completions.length-1) {
          self.currentSelection+=1;
        }
        render.call(self,self.getQueryString(), self.completions);
      }
      else if(event.keyCode == keyCodes.enter) {
        self.options.onSelect(self.completions[self.currentSelection]);
      }
      else if (event.keyCode == keyCodes.backspace || event.keyCode == keyCodes.deleteKey) {
        if (self.query.length > 0) {
          self.query.pop();
          self.options.source(self.getQueryString(), function(completions) {
            render.call(self, self.getQueryString(), completions);
          })
        }
      } 
      else if(keyChar!=="left" && keyChar!="right") {
        self.query.push(keyChar);
        self.options.source(self.getQueryString(), function(completions) {
          render.call(self, self.getQueryString(), completions);
        })
      } 
      
      event.stopPropagation();
      event.preventDefault();
      return true;
    }
  }

  var render = function(searchString, completions) {
    if(this.isShown) {
      this.searchString = searchString;
      this.completions = completions;
      var container = this.getDisplayElement();
      clearChildren(container);

      if(searchString===undefined) {
        this.container.className = "vimium-dialog";
        createDivInside(container).innerHTML=this.options.initialSearchText || "Begin typing";
      }
      else {
        this.container.className = "vimium-dialog vimium-completions";
        var searchBar = createDivInside(container);
        searchBar.innerHTML=searchString;
        searchBar.className="vimium-searchBar";

        searchResults = createDivInside(container);
        searchResults.className="vimium-searchResults";
        if(completions.length<=0) {
          var resultDiv = createDivInside(searchResults);
          resultDiv.className="vimium-noResults";
          resultDiv.innerHTML="No results found";
        }
        else {
          for(var i=0;i<completions.length;i++) {
            var resultDiv = createDivInside(searchResults);
            if(i===this.currentSelection) {
              resultDiv.className="vimium-selected";
            }
            resultDiv.innerHTML=this.options.renderOption(searchString, completions[i]);
          }
        }
      }

      container.style.top=Math.max(0,(window.innerHeight/2-container.clientHeight/2)) + "px";
      container.style.left=(window.innerWidth/2-container.clientWidth/2) + "px";
    }
  };
  var createDivInside = function(parent) {
    var element = document.createElement("div");
    parent.appendChild(element);
    return element;
  }
  
  var clearChildren = function(elem) {
    if (elem.hasChildNodes()) {
      while (elem.childNodes.length >= 1) {
        elem.removeChild(elem.firstChild);       
      } 
    }
  }
  
  var completionCSS = ".vimium-dialog {"+
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
    ".vimium-completions {"+
    "width:400px;"+
    "}"+
    ".vimium-completions .vimium-searchBar {"+
    "height: 15px;"+
    "border-bottom: 1px solid #b3b3b3;"+
    "}"+
    ".vimium-completions .vimium-searchResults {"+
    "}"+
    ".vimium-completions .vimium-searchResults .vimium-selected{"+
    "background-color:#aaa;"+
    "border-radius: 4px;" +
    "}"+
    ".vimium-completions div{"+
    "padding:4px;"+
    "}"+
    ".vimium-completions div strong{"+
    "color: black;" +
    "font-weight:bold;"+
    "}"+
    ".vimium-completions .vimium-noResults{"+
    "color:#555;"+
    "}";

  window.CompletionDialog = CompletionDialog;

}(window, document))
