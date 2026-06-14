import * as bgUtils from "./bg_utils.js";

export async function collapseTabGroup({ tab }) {
  if (!chrome.tabGroups || tab.groupId == -1) return;
  const tabs = await chrome.tabs.query({ currentWindow: true });
  let nextTab = tabs.find((t) => t.index > tab.index && t.groupId != tab.groupId) ||
    tabs.findLast((t) => t.index < tab.index && t.groupId != tab.groupId);
  if (!nextTab && !bgUtils.isFirefox()) {
    nextTab = await chrome.tabs.create({});
  }
  if (nextTab) await chrome.tabs.update(nextTab.id, { active: true });
  chrome.tabGroups.update(tab.groupId, { collapsed: true });
}

export function previousTabGroup({ tab }) {
  return goToTabGroup(tab, -1);
}

export function nextTabGroup({ tab }) {
  return goToTabGroup(tab, 1);
}

// Extend or shrink the tab selection (zz). Vim visual-mode semantics: tab.index is the anchor.
// - Right side extended? → extend further right.
// - Left side extended? → shrink from the left.
// - Nothing extended yet? → start extending right.
export async function selectNextTabForGroup({ tab }) {
  const tabs = await chrome.tabs.query({ windowId: tab.windowId });
  const highlighted = tabs.filter((t) => t.highlighted).map((t) => t.index);
  const anchor = tab.index;

  let next;
  if (highlighted.some((i) => i > anchor)) {
    const max = Math.max(...highlighted);
    if (max + 1 >= tabs.length) return;
    next = [...new Set([...highlighted, max + 1])];
  } else if (highlighted.some((i) => i < anchor)) {
    const min = Math.min(...highlighted);
    next = highlighted.filter((i) => i !== min);
  } else {
    if (anchor + 1 >= tabs.length) return;
    next = [anchor, anchor + 1];
  }

  await chrome.tabs.highlight({
    windowId: tab.windowId,
    tabs: [anchor, ...next.filter((i) => i !== anchor)],
  });
}

// Extend or shrink the tab selection (ZZ). Vim visual-mode semantics: tab.index is the anchor.
// - Left side extended? → extend further left.
// - Right side extended? → shrink from the right.
// - Nothing extended yet? → start extending left.
export async function selectPreviousTabForGroup({ tab }) {
  const tabs = await chrome.tabs.query({ windowId: tab.windowId });
  const highlighted = tabs.filter((t) => t.highlighted).map((t) => t.index);
  const anchor = tab.index;

  let next;
  if (highlighted.some((i) => i < anchor)) {
    const min = Math.min(...highlighted);
    if (min - 1 < 0) return;
    next = [...new Set([...highlighted, min - 1])];
  } else if (highlighted.some((i) => i > anchor)) {
    const max = Math.max(...highlighted);
    next = highlighted.filter((i) => i !== max);
  } else {
    if (anchor - 1 < 0) return;
    next = [anchor, anchor - 1];
  }

  await chrome.tabs.highlight({
    windowId: tab.windowId,
    tabs: [anchor, ...next.filter((i) => i !== anchor)],
  });
}

export async function moveTab({ count, tab, registryEntry }) {
  const direction = registryEntry.command === "moveTabLeft" ? -1 : 1;
  // Pinned tabs and environments without tabGroups API use the original simple logic.
  if (tab.pinned || !chrome.tabGroups) {
    const tabs = await chrome.tabs.query({ currentWindow: true });
    const pinnedCount = tabs.filter((t) => t.pinned).length;
    const minIndex = tab.pinned ? 0 : pinnedCount;
    const maxIndex = (tab.pinned ? pinnedCount : tabs.length) - 1;
    const pos = tabs.findIndex((t) => t.id === tab.id);
    const moveIndex = Math.max(minIndex, Math.min(maxIndex, pos + direction * count));
    return chrome.tabs.move(tab.id, { index: tabs[moveIndex].index });
  }
  for (let i = 0; i < count; i++) {
    await moveTabOneStep(tab, direction);
    tab = await chrome.tabs.get(tab.id);
  }
}

// Jump to the next (direction=1) or previous (direction=-1) tab group, wrapping circularly.
async function goToTabGroup(tab, direction) {
  if (!chrome.tabGroups) return;
  const tabs = await chrome.tabs.query({ currentWindow: true });
  const inDifferentGroup = (t) => t.groupId != -1 && t.groupId != tab.groupId;
  let target = direction > 0
    ? tabs.find((t) => t.index > tab.index && inDifferentGroup(t))
    : tabs.findLast((t) => t.index < tab.index && inDifferentGroup(t));
  if (!target) {
    target = direction > 0
      ? tabs.find((t) => inDifferentGroup(t))
      : tabs.findLast((t) => inDifferentGroup(t));
  }
  if (target) {
    await chrome.tabGroups.update(target.groupId, { collapsed: false });
    chrome.tabs.update(target.id, { active: true });
  }
}

// Move a non-pinned tab one step in the given direction, respecting tab group boundaries.
async function moveTabOneStep(tab, direction) {
  const tabs = await chrome.tabs.query({ currentWindow: true });
  const nonPinned = tabs.filter((t) => !t.pinned).sort((a, b) => a.index - b.index);
  const pos = nonPinned.findIndex((t) => t.id === tab.id);
  if (pos === -1) return;

  // Case 1: tab is inside a group — check if it's at the boundary.
  if (tab.groupId !== -1) {
    const groupTabs = nonPinned.filter((t) => t.groupId === tab.groupId);
    const atEdge = direction > 0
      ? tab.id === groupTabs.at(-1).id
      : tab.id === groupTabs[0].id;
    if (atEdge) {
      // Exit the group without moving — ungroup keeps the tab at its current index.
      await chrome.tabs.ungroup([tab.id]);
    } else {
      const neighbor = nonPinned[pos + direction];
      if (neighbor) await chrome.tabs.move(tab.id, { index: neighbor.index });
    }
    return;
  }

  // Case 2: tab is not in any group.
  const neighbor = nonPinned[pos + direction];
  if (!neighbor) return; // at window edge

  if (neighbor.groupId === -1) {
    await chrome.tabs.move(tab.id, { index: neighbor.index });
    return;
  }

  // Neighbor belongs to a group.
  const group = await chrome.tabGroups.get(neighbor.groupId);
  const groupTabs = nonPinned.filter((t) => t.groupId === neighbor.groupId);

  if (group.collapsed) {
    // Skip over the entire collapsed group: land on the far side of it.
    const edgeTab = direction > 0 ? groupTabs.at(-1) : groupTabs[0];
    const edgePos = nonPinned.findIndex((t) => t.id === edgeTab.id);
    const afterGroup = nonPinned[edgePos + direction];
    if (!afterGroup) {
      // Group is flush against the window edge — land just past it.
      await chrome.tabs.move(tab.id, { index: edgeTab.index });
      return;
    }
    // afterGroup.index - direction places the tab immediately next to afterGroup
    // on the group's side, accounting for the index shift caused by the move.
    await chrome.tabs.move(tab.id, { index: afterGroup.index - direction });
  } else {
    // Enter the open group. Chrome keeps the tab at its current adjacent position
    // and adds it to the group, so no explicit move is needed.
    await chrome.tabs.group({ tabIds: [tab.id], groupId: neighbor.groupId });
  }
}
