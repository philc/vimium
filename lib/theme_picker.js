// A stylable replacement for native <select> elements, used by the theme pickers. The option popup
// of a native <select> cannot be styled with CSS, so this component renders its own list, which
// picks up the styling of the active theme. The container element should have the "theme-picker"
// class and is populated by this function.
export function createThemePicker(container, { options, value, onChange }) {
  container.innerHTML = "";

  const valueEl = document.createElement("span");
  valueEl.className = "theme-picker-value";

  const listEl = document.createElement("ul");
  listEl.className = "theme-picker-options";
  listEl.hidden = true;

  container.appendChild(valueEl);
  container.appendChild(listEl);

  let currentValue = value;
  let highlightedIndex = -1;

  const optionEls = options.map((option) => {
    const optionEl = document.createElement("li");
    optionEl.setAttribute("role", "option");
    optionEl.textContent = option.label;
    optionEl.addEventListener("click", (event) => {
      event.stopPropagation();
      select(option.value);
    });
    listEl.appendChild(optionEl);
    return optionEl;
  });

  const indexOfValue = (value) => Math.max(0, options.findIndex((option) => option.value == value));

  function render() {
    valueEl.textContent = options[indexOfValue(currentValue)].label;
    optionEls.forEach((optionEl, i) => {
      const isSelected = options[i].value == currentValue;
      optionEl.classList.toggle("selected", isSelected);
      optionEl.classList.toggle("highlighted", i === highlightedIndex);
      optionEl.setAttribute("aria-selected", isSelected);
    });
  }

  function select(value) {
    currentValue = value;
    close();
    render();
    onChange(value);
  }

  const isOpen = () => !listEl.hidden;

  const onOutsideClick = (event) => {
    if (!container.contains(event.target)) close();
  };

  function open() {
    listEl.hidden = false;
    container.setAttribute("aria-expanded", "true");
    highlightedIndex = indexOfValue(currentValue);
    render();
    document.addEventListener("pointerdown", onOutsideClick, true);
  }

  function close() {
    listEl.hidden = true;
    container.setAttribute("aria-expanded", "false");
    highlightedIndex = -1;
    document.removeEventListener("pointerdown", onOutsideClick, true);
    render();
  }

  container.addEventListener("click", () => {
    if (isOpen()) {
      close();
    } else {
      open();
    }
  });

  container.addEventListener("keydown", (event) => {
    if (!isOpen()) {
      if (["Enter", " ", "ArrowDown", "ArrowUp"].includes(event.key)) {
        event.preventDefault();
        open();
      }
      return;
    }
    switch (event.key) {
      case "Escape":
        event.preventDefault();
        close();
        break;
      case "ArrowDown":
      case "ArrowUp":
        event.preventDefault();
        const delta = event.key === "ArrowDown" ? 1 : -1;
        highlightedIndex = Math.min(
          options.length - 1,
          Math.max(0, highlightedIndex + delta),
        );
        render();
        break;
      case "Enter":
      case " ":
        event.preventDefault();
        if (highlightedIndex >= 0) {
          select(options[highlightedIndex].value);
        }
        break;
    }
  });

  render();

  return {
    setValue(value) {
      currentValue = value;
      render();
    },
    getValue() {
      return currentValue;
    },
  };
}
