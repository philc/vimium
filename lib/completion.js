var completionProviders = {
  bookmarks: (function() {
    function traverseTree(bookmarks, callback) {
      for (var i = 0; i < bookmarks.length; ++i) {
        callback(bookmarks[i]);
        if (typeof bookmarks[i].children === "undefined")
          continue;
        traverseTree(bookmarks[i].children, callback);
      }
    };

    return function(callback) {
      chrome.bookmarks.getTree(function(bookmarks) {
        traverseTree(bookmarks, function(bookmark) {
          if (typeof bookmark.url === "undefined")
            return;

          callback({
            str:    bookmark.url + ' (' + bookmark.title + ')',
            action: bookmark.url,
            type:   'bookmark',
          });
        });
      });
    };
  })(),

  history: function(callback) {
    chrome.history.search({ text: '',
                            maxResults: 1000000000 },
                          function(history) {
      // sort by visit cound descending
      history.sort(function(a, b) {
        // visitCount may be undefined
        var visitCountForA = a.visitCount || 0;
        var visitCountForB = a.visitCount || 0;
        return visitCountForB - visitCountForA;
      });
      for (var i = 0; i < history.length; ++i) {
        callback({
          str:    history[i].url + ' (' + history[i].title + ')',
          action: history[i].url,
          type:   'history',
        });
      }
    });
  },
};

function fuzzyComplete(query, completions) {
  var regex = new RegExp(query.split('').join('.*'), 'i');
  var results = [];
  for (var i = 0; i < completions.length; ++i) {
    if (regex.test(completions[i].str))
      results.push(completions[i]);
  };

  // sort by length ascending
  results.sort(function(a, b) {
    return a.str.length - b.str.length;
  });
  return results;
}
