function populatePage() {
  const h2s = document.querySelectorAll("h2");
  const byGroup = Object.groupBy(allCommands, (el) => el.group);

  const template = document.querySelector("template#command").content;

  for (const h2 of Array.from(h2s)) {
    const group = h2.dataset["group"];
    let commands = byGroup[group];
    // Display them in alphabetical order.
    commands = commands.sort((a, b) => b.name.localeCompare(a.name));
    for (const command of commands) {
      const el = template.cloneNode(true);
      el.querySelector("h3 code").innerText = command.name;
      el.querySelector(".desc").innerText = command.desc;
      if (command.options) {
        const ul = el.querySelector(".options ul");
        for (const [name, desc] of Object.entries(command.options)) {
          const li = document.createElement("li");
          li.innerHTML = desc;
          ul.appendChild(li);
        }
      } else {
        el.querySelector(".options").remove();
      }
      h2.after(el);
    }
  }
}

document.addEventListener("DOMContentLoaded", async () => {
  await Settings.onLoaded();
  DomUtils.injectUserCss();
  populatePage();
  // await Commands.init();
  // await OptionsPage.init();
});
