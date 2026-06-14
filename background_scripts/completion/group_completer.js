import * as ranking from "./ranking.js";
import { Suggestion } from "./completers.js";

const GROUP_COLORS = ["grey", "blue", "red", "yellow", "green", "pink", "purple", "cyan", "orange"];

const COLOR_CSS = {
  grey: "#5F6368", blue: "#1A73E8", red: "#D93025", yellow: "#F9AB00",
  green: "#1E8E3E", pink: "#D01884", purple: "#8430CE", cyan: "#007B83", orange: "#E37400",
};

async function queryCurrentWindow() {
  const win = await chrome.windows.getLastFocused({ populate: false });
  const [groups, tabs] = await Promise.all([
    chrome.tabGroups.query({ windowId: win.id }),
    chrome.tabs.query({ windowId: win.id }),
  ]);
  return { groups, tabs };
}

function buildFirstTabMap(tabs) {
  const map = new Map();
  for (const tab of tabs.sort((a, b) => a.index - b.index)) {
    if (tab.groupId !== -1 && !map.has(tab.groupId)) {
      map.set(tab.groupId, tab);
    }
  }
  return map;
}

function esc(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function colorSwatch(color) {
  const bg = COLOR_CSS[color] ?? "#888";
  return `<span class="group-color-swatch" style="background:${bg}"></span>`;
}

function groupHtml(group, url) {
  const source = `${colorSwatch(group.color)}${esc(group.color)}`;
  const name = esc(group.title || `(${group.color})`);
  return `<div class="top-half"><span class="source">${source}</span><span class="title">${name}</span></div>` +
    `<div class="bottom-half"><span class="url">${esc(url)}</span></div>`;
}

// ZG: navigate to a tab group by name.
export class TabGroupCompleter {
  showResultsWithNoQuery = true;

  async filter({ queryTerms }) {
    if (!chrome.tabGroups) return [];
    const { groups, tabs } = await queryCurrentWindow();
    const firstTabByGroup = buildFirstTabMap(tabs);
    return groups
      .filter((g) => queryTerms.length === 0 || ranking.matches(queryTerms, g.title ?? "", g.color))
      .map((group) => {
        const firstTab = firstTabByGroup.get(group.id);
        const url = firstTab?.url ?? "";
        const s = new Suggestion({
          queryTerms,
          description: group.color || "tab group",
          url,
          title: group.title || `(${group.color})`,
          tabId: firstTab?.id,
          deDuplicate: false,
        });
        s.html = groupHtml(group, url);
        s.relevancy = 1;
        return s;
      });
  }
}

// zg step 1: assign highlighted tabs to an existing group, or start creating a new one.
export class TabGroupAssignCompleter {
  showResultsWithNoQuery = true;

  async filter({ queryTerms, query }) {
    if (!chrome.tabGroups) return [];
    const { groups, tabs } = await queryCurrentWindow();
    const firstTabByGroup = buildFirstTabMap(tabs);
    const existingMatches = groups
      .filter((g) => queryTerms.length === 0 || ranking.matches(queryTerms, g.title ?? "", g.color))
      .map((group) => {
        const firstTab = firstTabByGroup.get(group.id);
        const url = firstTab?.url ?? "";
        const s = new Suggestion({
          queryTerms,
          description: group.color || "tab group",
          url,
          title: group.title || `(${group.color})`,
          deDuplicate: false,
          groupData: { action: "addToGroup", groupId: group.id },
        });
        s.html = groupHtml(group, url);
        s.relevancy = 1;
        return s;
      });

    const name = query.trim();
    if (name) {
      const create = new Suggestion({
        queryTerms: [],
        description: "new group",
        url: "",
        title: `Create "${name}"`,
        deDuplicate: false,
        groupData: { action: "createGroup", name },
      });
      create.html = `<div class="top-half"><span class="source">new group</span>` +
        `<span class="title">${esc(`Create "${name}"`)}</span></div>`;
      create.relevancy = 0;
      return [...existingMatches, create];
    }
    return existingMatches;
  }
}

// zg step 2: pick a color for a new group.
export class TabGroupColorCompleter {
  showResultsWithNoQuery = true;

  async filter({ queryTerms }) {
    return GROUP_COLORS
      .filter((c) => queryTerms.length === 0 || c.includes(queryTerms[0]?.toLowerCase() ?? ""))
      .map((color, i) => {
        const s = new Suggestion({
          queryTerms,
          description: "color",
          url: "",
          title: color,
          deDuplicate: false,
          groupData: { action: "setColor", color },
        });
        s.html = `<div class="top-half"><span class="source">${colorSwatch(color)}</span>` +
          `<span class="title">${esc(color)}</span></div>`;
        s.relevancy = GROUP_COLORS.length - i;
        return s;
      });
  }
}
