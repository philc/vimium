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

// Move the entire highlighted tab block one slot in the given direction, count times.
// Uses a swap strategy: instead of moving all selected tabs, move the single adjacent
// non-selected tab to the opposite side of the block.
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
  if (direction > 0) {
    // Move right: take the tab just right of the block and place it left of the block.
    const rightEdge = selected[selected.length - 1];
    const rightPos = nonPinned.findIndex((t) => t.id === rightEdge.id);
    const neighbor = nonPinned[rightPos + 1];
    if (!neighbor) return;
    await chrome.tabs.move(neighbor.id, { index: selected[0].index });
  } else {
    // Move left: take the tab just left of the block and place it right of the block.
    const leftEdge = selected[0];
    const leftPos = nonPinned.findIndex((t) => t.id === leftEdge.id);
    const neighbor = nonPinned[leftPos - 1];
    if (!neighbor) return;
    await chrome.tabs.move(neighbor.id, { index: selected[selected.length - 1].index });
  }
}
