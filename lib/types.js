// A centralized file of types which can be shared by both content scripts and background pages.

globalThis.VomnibarShowOptions = {
  // The name of the completer to fetch results from.
  completer: "string",
  // Text to prefill the Vomnibar with.
  query: "string",
  // Text the user typed while the Vomnibar was loading. Unlike `query`, it's handled as typing, so
  // e.g. a search engine keyword in it takes effect.
  typedText: "string",
  // Whether to open the result in a new tab.
  newTab: "boolean",
  // Whether to select the first entry.
  selectFirst: "boolean",
  // A keyword which will scope the search to a UserSearchEngine.
  keyword: "string",
  // The count typed before launching command mode, used to repeat the selected command.
  prefixCount: "number",
};
