import * as completionEngines from "./completion_engines.js";

// This is a wrapper class for completion engines. It handles the case where a custom search engine
// includes a prefix query term (or terms). For example:
//
//   https://www.google.com/search?q=javascript+%s
//
// In this case, we get better suggestions if we include the term "javascript" in queries sent to
// the completion engine. This wrapper handles adding such prefixes to completion-engine queries and
// removing them from the resulting suggestions.
class EnginePrefixWrapper {
  constructor(searchUrl, engine) {
    this.searchUrl = searchUrl;
    this.engine = engine;
  }

  getUrl(queryTerms) {
    // This tests whether @searchUrl contains something of the form "...=abc+def+%s...", from which
    // we extract a prefix of the form "abc def ".
    if (/\=.+\+%s/.test(this.searchUrl)) {
      let terms = this.searchUrl.replace(/\+%s.*/, "");
      terms = terms.replace(/.*=/, "");
      terms = terms.replace(/\+/g, " ");

      queryTerms = [...terms.split(" "), ...queryTerms];
      const prefix = `${terms} `;

      this.transformSuggestionsFn = (suggestions) => {
        return suggestions
          .filter((s) => s.startsWith(prefix))
          .map((s) => s.slice(prefix.length));
      };
    }

    return this.engine.getUrl(queryTerms);
  }

  parse(responseText) {
    const suggestions = this.engine.parse(responseText);
    return this.transformSuggestionsFn ? this.transformSuggestionsFn(suggestions) : suggestions;
  }
}

let debug = false;
const inTransit = {};
const completionCache = new SimpleCache(2 * 60 * 60 * 1000, 5000); // Two hours, 5000 entries.
const engineCache = new SimpleCache(1000 * 60 * 60 * 1000); // 1000 hours.

// The amount of time to wait for new requests before launching the current request (for example,
// if the user is still typing).
const DELAY = 100;

// This gets incremented each time we make a request to the completion engine. This allows us to
// dedupe requets which overlap, which is the case when the user is typing fast.
let requestId = 0;

async function get(url) {
  const timeoutDuration = 2500;
  const controller = new AbortController();
  let isError = false;
  let responseText;
  const timer = Utils.setTimeout(timeoutDuration, () => controller.abort());

  try {
    const response = await fetch(url, { signal: controller.signal });
    responseText = await response.text();
  } catch {
    // Fetch throws an error if the network is unreachable, etc.
    isError = true;
  }

  clearTimeout(timer);

  return isError ? null : responseText;
}

// Look up the completion engine for this searchUrl.
function lookupEngine(searchUrl) {
  if (engineCache.has(searchUrl)) {
    return engineCache.get(searchUrl);
  } else {
    for (const engineClass of completionEngines.list) {
      const engine = new engineClass();
      if (engine.match(searchUrl)) {
        return engineCache.set(searchUrl, engine);
      }
    }
  }
}

// This is the main entry point.
//  - searchUrl is the search engine's URL, e.g. Settings.get("searchUrl"), or a custom search
//    engine's URL. This is only used as a key for determining the relevant completion engine.
//  - queryTerms are the query terms.
export async function complete(searchUrl, queryTerms) {
  const query = queryTerms.join(" ").toLowerCase();

  // We don't complete queries which are too short: the results are usually useless.
  if (query.length < 4) return [];

  // We don't complete regular URLs or Javascript URLs.
  if (queryTerms.length == 1 && await UrlUtils.isUrl(query)) return [];
  if (UrlUtils.hasJavascriptProtocol(query)) return [];

  const engine = lookupEngine(searchUrl);
  if (!engine) return [];

  const completionCacheKey = JSON.stringify([searchUrl, queryTerms]);
  if (completionCache.has(completionCacheKey)) {
    if (debug) console.log("hit", completionCacheKey);
    return completionCache.get(completionCacheKey);
  }

  const createTimeoutPromise = (ms) => {
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  };

  requestId++;
  const lastRequestId = requestId;

  // We delay sending a completion request in case the user is still typing.
  await createTimeoutPromise(DELAY);

  // If the user has issued a new query while we were waiting, then this query is old; abort it.
  if (lastRequestId != requestId) return [];

  const engineWrapper = new EnginePrefixWrapper(searchUrl, engine);
  const url = engineWrapper.getUrl(queryTerms);

  if (debug) console.log("GET", url);
  const responseText = await get(url);

  // Parsing the response may fail if we receive an unexpectedly-formatted response. In all cases,
  // we fall back to the catch clause, below. Therefore, we "fail safe" in the case of incorrect
  // or out-of-date completion engine implementations.
  let suggestions = [];
  let isError = responseText == null;
  if (!isError) {
    try {
      suggestions = engineWrapper.parse(responseText)
        // Make all suggestions lower case. It looks odd when suggestions from one
        // completion engine are upper case, and those from another are lower case.
        .map((s) => s.toLowerCase())
        // Filter out the query itself. It's not adding anything.
        .filter((s) => s !== query);
    } catch (error) {
      if (debug) console.log("error:", error);
      isError = true;
    }
  }
  if (isError) {
    // We allow failures to be cached too, but remove them after just thirty seconds.
    Utils.setTimeout(
      30 * 1000,
      () => completionCache.set(completionCacheKey, null),
    );
  }

  completionCache.set(completionCacheKey, suggestions);
  return suggestions;
}

// Cancel any pending (ie. blocked on @delay) queries. Does not cancel in-flight queries. This is
// called whenever the user is typing.
export function cancel() {
  requestId++;
}
