// Extend or shrink the tab selection (zz). Vim visual-mode semantics: tab.index is the anchor.
// - Right side extended? → extend further right.
// - Left side extended? → shrink from the left.
// - Nothing extended yet? → start extending right.
export async function selectNextTabForGroup({ tab, count }) {
  for (let i = 0; i < count; i++) {
    await selectNextTabOnce(tab);
  }
}

async function selectNextTabOnce(tab) {
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
export async function selectPreviousTabForGroup({ tab, count }) {
  for (let i = 0; i < count; i++) {
    await selectPreviousTabOnce(tab);
  }
}

async function selectPreviousTabOnce(tab) {
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

export async function moveTabSelection({ count, tab, registryEntry }) {
  const direction = registryEntry.command === "moveTabLeft" ? -1 : 1;
  let selected = await getSelectedNonPinned(tab.windowId);
  for (let i = 0; i < count; i++) {
    await moveSelectionOneStep(selected, direction);
    selected = await getSelectedNonPinned(tab.windowId);
  }
}

async function getSelectedNonPinned(windowId) {
  const tabs = await chrome.tabs.query({ windowId });
  return tabs.filter((t) => t.highlighted && !t.pinned).sort((a, b) => a.index - b.index);
}

async function moveSelectionOneStep(selected, direction) {
  const allTabs = await chrome.tabs.query({ windowId: selected[0].windowId });
  const nonPinned = allTabs.filter((t) => !t.pinned).sort((a, b) => a.index - b.index);

  const selGroupId = selected[0].groupId;
  const selectionInGroup = selGroupId !== -1 && selected.every((t) => t.groupId === selGroupId);

  if (direction > 0) {
    const rightEdge = selected[selected.length - 1];
    const rightPos = nonPinned.findIndex((t) => t.id === rightEdge.id);
    const neighbor = nonPinned[rightPos + 1];

    if (selectionInGroup) {
      if (neighbor && neighbor.groupId === selGroupId) {
        await chrome.tabs.move(neighbor.id, { index: selected[0].index });
      } else if (neighbor) {
        // Rightmost-first: each tab is the last remaining group member when ungrouped,
        // so Chrome places it just after itself — no reposition needed.
        for (let i = selected.length - 1; i >= 0; i--) await chrome.tabs.ungroup([selected[i].id]);
      }
      return;
    }

    if (!neighbor) return;

    if (neighbor.groupId === -1) {
      await chrome.tabs.move(neighbor.id, { index: selected[0].index });
    } else if (chrome.tabGroups) {
      const group = await chrome.tabGroups.get(neighbor.groupId);
      const groupTabs = nonPinned.filter((t) => t.groupId === neighbor.groupId);
      if (group.collapsed) {
        // Individual moves rightmost-first: a batch move would drop the first tab between
        // group members, causing Chrome to absorb it into the group and uncollapse it.
        const groupLastIndex = groupTabs[groupTabs.length - 1].index;
        for (let i = 0; i < selected.length; i++) {
          await chrome.tabs.move(selected[selected.length - 1 - i].id, { index: groupLastIndex - i });
        }
      } else {
        await chrome.tabs.group({ tabIds: selected.map((t) => t.id), groupId: neighbor.groupId });
      }
    }
  } else {
    const leftEdge = selected[0];
    const leftPos = nonPinned.findIndex((t) => t.id === leftEdge.id);
    const neighbor = nonPinned[leftPos - 1];

    if (selectionInGroup) {
      if (neighbor && neighbor.groupId === selGroupId) {
        await chrome.tabs.move(neighbor.id, { index: selected[selected.length - 1].index });
      } else if (neighbor) {
        // Leftmost-first: each tab is the first remaining group member when ungrouped,
        // so Chrome places it just before itself — no reposition needed.
        for (const t of selected) await chrome.tabs.ungroup([t.id]);
      }
      return;
    }

    if (!neighbor) return;

    if (neighbor.groupId === -1) {
      await chrome.tabs.move(neighbor.id, { index: selected[selected.length - 1].index });
    } else if (chrome.tabGroups) {
      const group = await chrome.tabGroups.get(neighbor.groupId);
      const groupTabs = nonPinned.filter((t) => t.groupId === neighbor.groupId);
      if (group.collapsed) {
        // Individual moves leftmost-first: same reason as the right case above.
        const groupFirstIndex = groupTabs[0].index;
        for (let i = 0; i < selected.length; i++) {
          await chrome.tabs.move(selected[i].id, { index: groupFirstIndex + i });
        }
      } else {
        await chrome.tabs.group({ tabIds: selected.map((t) => t.id), groupId: neighbor.groupId });
      }
    }
  }
}
