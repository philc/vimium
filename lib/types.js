// A centralized file of types which can be shared by both content scripts and background pages.

globalThis.VomnibarShowOptions = {
  // The name of the completer to fetch results from.
  completer: "string",
  // Text to prefill the Vomnibar with.
  query: "string",
  // Whether to open the result in a new tab.
  newTab: "boolean",
  // Whether to select the first entry.
  selectFirst: "boolean",
  // A keyword which will scope the search to a UserSearchEngine.
  keyword: "string",
};
