import "./all_content_scripts.js";
import { allCommands } from "../background_scripts/all_commands.js";

// The ordering we show key bindings is alphanumerical, except that special keys sort to the end.
function compareKeys(a, b) {
  a = a.replace("<", "~");
  b = b.replace("<", "~");
  if (a < b) {
    return -1;
  } else if (b < a) {
    return 1;
  } else {
    return 0;
  }
}

function replaceBackticksWithCodeTags(str) {
  let count = 0;
  return str.replace(/`/g, (match) => {
    count++;
    return count % 2 === 1 ? "<code>" : "</code>";
  });
}

async function populatePage() {
  const h2s = document.querySelectorAll("h2");
  const byGroup = Object.groupBy(allCommands, (el) => el.group);
  const commandToOptionsToKeys =
    (await chrome.storage.session.get("commandToOptionsToKeys")).commandToOptionsToKeys;

  const commandTemplate = document.querySelector("template#command").content;
  const keysTemplate = document.querySelector("template#keys").content;

  for (const h2 of Array.from(h2s)) {
    const group = h2.dataset["group"];
    let commands = byGroup[group];
    // Display them in alphabetical order.
    commands = commands.sort((a, b) => b.name.localeCompare(a.name));
    for (const command of commands) {
      // Here, we're going to list all of the keys bound to this command, and for now, we're not
      // going to visually distinguish versions of the command with options and versions without.
      const keys = Object.values(commandToOptionsToKeys[command.name] || {})
        .flat(1);
      const el = commandTemplate.cloneNode(true);
      // Used for linking to commands using the URL fragment, and by the tests.
      el.querySelector(".command").id = command.name;
      el.querySelector("h3 code").textContent = command.name;

      const keysEl = el.querySelector(".key-bindings");
      for (const key of keys.sort(compareKeys)) {
        const node = keysTemplate.cloneNode(true);
        node.querySelector(".key").textContent = key;
        keysEl.appendChild(node);
      }

      el.querySelector(".desc").textContent = command.desc;
      if (command.details) {
        el.querySelector(".details").textContent = command.details;
      }

      if (command.options) {
        const ul = el.querySelector(".options ul");
        for (const [name, desc] of Object.entries(command.options)) {
          const li = document.createElement("li");
          li.innerHTML = `<code>${name}</code>: ` + replaceBackticksWithCodeTags(desc);
          ul.appendChild(li);
        }
      } else {
        el.querySelector(".options").remove();
      }
      h2.after(el);
    }
  }
}

const testEnv = globalThis.window == null;
if (!testEnv) {
  document.addEventListener("DOMContentLoaded", async () => {
    await Settings.onLoaded();
    DomUtils.injectUserCss();
    await populatePage();
  });
}

export { populatePage };
