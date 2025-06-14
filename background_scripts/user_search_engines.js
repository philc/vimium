import "../lib/url_utils.js";
import * as commands from "./commands.js";

// A struct representing a search engine entry in the "searchEngine" setting.
export class UserSearchEngine {
  keyword;
  url;
  description;
  constructor(o) {
    Object.seal(this);
    if (o) Object.assign(this, o);
  }
}

// Parses a user's search engine configuration from Settings, and stores the parsed results.
// TODO(philc): Should this be responsible for updating itself when Settings changes, rather than
// the callers doing so? Or, remove this class and re-parse the configuration every keystroke in
// Vomnibar, so we don't introduce another layer of caching in the code.
export let keywordToEngine = {};

// Returns a result of the shape: { keywordToEngine, validationErrors }.
export function parseConfig(configText) {
  const results = {};
  const errors = [];
  for (const line of commands.parseLines(configText)) {
    const tokens = line.split(/\s+/);
    if (tokens.length < 2) {
      errors.push(`This line has less than two tokens: ${line}`);
      continue;
    }
    if (!tokens[0].includes(":")) {
      errors.push(`This line doesn't include a ":" character: ${line}`);
      continue;
    }
    const keyword = tokens[0].split(":")[0];
    const url = tokens[1];
    const description = tokens.length > 2 ? tokens.slice(2).join(" ") : `search (${keyword})`;

    if (!UrlUtils.urlHasProtocol(url) && !UrlUtils.hasJavascriptProtocol(url)) {
      errors.push(`This search engine doesn't have a valid URL: ${line}`);
      continue;
    }
    results[keyword] = new UserSearchEngine({ keyword, url, description });
  }
  return {
    keywordToEngine: results,
    validationErrors: errors,
  };
}

export function set(searchEnginesConfigText) {
  keywordToEngine = parseConfig(searchEnginesConfigText).keywordToEngine;
}
