// A completion engine provides search suggestions for a custom search engine. A custom search
// engine is identified by a "searchUrl". An "engineUrl" is used for fetching suggestions, whereas a
// "searchUrl" is used for the actual search itself.
//
// Each completion engine defines:
//
//   1. An "engineUrl". This is the URL to use for search completions and is passed as the option
//      "engineUrl" to the "BaseEngine" constructor.
//
//   2. One or more regular expressions which define the custom search engine URLs for which the
//      completion engine will be used. This is passed as the "regexps" option to the "BaseEngine"
//      constructor.
//
//   3. A "parse" function. This takes the text body of an HTTP response and returns a list of
//      suggestions (a list of strings). This method is always executed within the context of a
//      try/catch block, so errors do not propagate.
//
//   4. Each completion engine *must* include an example custom search engine. The example must
//      include an example "keyword" and an example "searchUrl", and may include an example
//      "description" and an "explanation". This info is shown as documentation to the user.
//
// Each new completion engine must be added to the list "CompletionEngines" at the bottom of this
// file.
//
// The lookup logic which uses these completion engines is in "./completion_search.js".
//

// A base class for common regexp-based matching engines. "options" must define:
//   options.engineUrl: the URL to use for the completion engine. This must be a string.
//   options.regexps: one or regular expressions.  This may either a single string or a list of strings.
//   options.example: an example object containing at least "keyword" and "searchUrl", and optional "description".
// TODO(philc): This base class is doing very little. We should remove it and use composition.
class BaseEngine {
  constructor(options) {
    Object.assign(this, options);
    this.regexps = this.regexps.map((regexp) => new RegExp(regexp));
  }

  match(searchUrl) {
    return Utils.matchesAnyRegexp(this.regexps, searchUrl);
  }
  getUrl(queryTerms) {
    return UrlUtils.createSearchUrl(queryTerms, this.engineUrl);
  }
}

class Google extends BaseEngine {
  constructor() {
    super({
      engineUrl: "http://suggestqueries.google.com/complete/search?client=chrome&q=%s",
      regexps: ["^https?://[a-z]+\\.google\\.(com|ie|co\\.(uk|jp)|ca|com\\.au)/"],
      example: {
        searchUrl: "https://www.google.com/search?q=%s",
        keyword: "g",
      },
    });
  }

  parse(text) {
    return JSON.parse(text)[1];
  }
}

const googleMapsPrefix = "map of ";

class GoogleMaps extends BaseEngine {
  constructor() {
    super({
      engineUrl:
        `http://suggestqueries.google.com/complete/search?client=chrome&ds=yt&q=${googleMapsPrefix}%s`,
      regexps: ["^https?://[a-z]+\\.google\\.(com|ie|co\\.(uk|jp)|ca|com\\.au)/maps"],
      example: {
        searchUrl: "https://www.google.com/maps?q=%s",
        keyword: "m",
        explanation: `\
This uses regular Google completion, but prepends the text "<tt>map of </tt>" to the query.  It works
well for places, countries, states, geographical regions and the like, but will not perform address
search.\
`,
      },
    });
  }

  parse(text) {
    return JSON.parse(text)[1]
      .filter((suggestion) => suggestion.startsWith(googleMapsPrefix))
      .map((suggestion) => suggestion.slice(googleMapsPrefix));
  }
}

class Youtube extends BaseEngine {
  constructor() {
    super({
      engineUrl: "http://suggestqueries.google.com/complete/search?client=chrome&ds=yt&q=%s",
      regexps: ["^https?://[a-z]+\\.youtube\\.com/results"],
      example: {
        searchUrl: "https://www.youtube.com/results?search_query=%s",
        keyword: "y",
      },
    });
  }

  parse(text) {
    return JSON.parse(text)[1];
  }
}

class Wikipedia extends BaseEngine {
  constructor() {
    super({
      engineUrl: "https://en.wikipedia.org/w/api.php?action=opensearch&format=json&search=%s",
      regexps: ["^https?://[a-z]+\\.wikipedia\\.org/"],
      example: {
        searchUrl: "https://www.wikipedia.org/w/index.php?title=Special:Search&search=%s",
        keyword: "w",
      },
    });
  }

  parse(text) {
    return JSON.parse(text)[1];
  }
}

class Bing extends BaseEngine {
  constructor() {
    super({
      engineUrl: "https://api.bing.com/osjson.aspx?query=%s",
      regexps: ["^https?://www\\.bing\\.com/search"],
      example: {
        searchUrl: "https://www.bing.com/search?q=%s",
        keyword: "b",
      },
    });
  }

  parse(text) {
    return JSON.parse(text)[1];
  }
}

class Amazon extends BaseEngine {
  constructor() {
    super({
      engineUrl:
        "https://completion.amazon.com/api/2017/suggestions?mid=ATVPDKIKX0DER&alias=aps&prefix=%s",
      regexps: ["^https?://(www|smile)\\.amazon\\.(com|co\\.uk|ca|de|com\\.au)/s/"],
      example: {
        searchUrl: "https://www.amazon.com/s/?field-keywords=%s",
        keyword: "a",
      },
    });
  }

  parse(text) {
    return JSON.parse(text).suggestions.map((suggestion) => suggestion.value);
  }
}

class DuckDuckGo extends BaseEngine {
  constructor() {
    super({
      engineUrl: "https://duckduckgo.com/ac/?q=%s",
      regexps: ["^https?://([a-z]+\\.)?duckduckgo\\.com/"],
      example: {
        searchUrl: "https://duckduckgo.com/?q=%s",
        keyword: "d",
      },
    });
  }

  parse(text) {
    return JSON.parse(text).map((suggestion) => suggestion.phrase);
  }
}

class Webster extends BaseEngine {
  constructor() {
    super({
      engineUrl: "https://www.merriam-webster.com/lapi/v1/mwol-search/autocomplete?search=%s",
      regexps: ["^https?://www.merriam-webster.com/dictionary/"],
      example: {
        searchUrl: "https://www.merriam-webster.com/dictionary/%s",
        keyword: "dw",
        description: "Dictionary",
      },
    });
  }

  parse(text) {
    return JSON.parse(text).docs.map((suggestion) => suggestion.word);
  }
}

// Qwant is a privacy-friendly search engine.
class Qwant extends BaseEngine {
  constructor() {
    super({
      engineUrl: "https://api.qwant.com/api/suggest?q=%s",
      regexps: ["^https?://www\\.qwant\\.com/"],
      example: {
        searchUrl: "https://www.qwant.com/?q=%s",
        keyword: "qw",
      },
    });
  }

  parse(text) {
    return JSON.parse(text).data.items.map((suggestion) => suggestion.value);
  }
}

// Brave is a privacy-friendly search engine.
class Brave extends BaseEngine {
  constructor() {
    super({
      engineUrl: "https://search.brave.com/api/suggest?rich=false&q=%s",
      regexps: ["^https?://search\\.brave\\.com/"],
      example: {
        searchUrl: "https://search.brave.com/search?q=%s",
        keyword: "br",
      },
    });
  }

  parse(text) {
    return JSON.parse(text)[1];
  }
}

// On the user-facing documentation page pages/completion_engines.html, these completion search
// engines will be shown to the user in this order.
const CompletionEngines = [
  Youtube,
  GoogleMaps,
  Google,
  DuckDuckGo,
  Wikipedia,
  Bing,
  Amazon,
  Webster,
  Qwant,
  Brave,
];

globalThis.CompletionEngines = CompletionEngines;

export { Amazon, Brave, DuckDuckGo, Qwant, Webster };
