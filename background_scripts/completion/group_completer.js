import * as ranking from "./ranking.js";
import { Suggestion } from "./completers.js";

export class TabGroupCompleter {
  async filter({ queryTerms }) {
    if (!chrome.tabGroups) return [];
    const [groups, tabs] = await Promise.all([
      chrome.tabGroups.query({ windowId: chrome.windows.WINDOW_ID_CURRENT }),
      chrome.tabs.query({ currentWindow: true }),
    ]);
    // Build a map from groupId → first tab in that group (by tab index).
    const firstTabByGroup = new Map();
    for (const tab of tabs.sort((a, b) => a.index - b.index)) {
      if (tab.groupId !== -1 && !firstTabByGroup.has(tab.groupId)) {
        firstTabByGroup.set(tab.groupId, tab);
      }
    }
    return groups
      .filter((g) => queryTerms.length === 0 || ranking.matches(queryTerms, g.title ?? "", g.color))
      .map((group) => {
        const firstTab = firstTabByGroup.get(group.id);
        const label = group.title || `(${group.color})`;
        const suggestion = new Suggestion({
          queryTerms,
          description: "tab group",
          url: firstTab?.url ?? "",
          title: label,
          tabId: firstTab?.id,
          deDuplicate: false,
        });
        suggestion.relevancy = 1;
        return suggestion;
      });
  }
}
