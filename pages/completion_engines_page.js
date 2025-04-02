import "./all_content_scripts.js";
import * as completionEngines from "../background_scripts/completion_engines.js";

function cleanUpRegexp(re) {
  return re.toString()
    .replace(/^\//, "")
    .replace(/\/$/, "")
    .replace(/\\\//g, "/");
}

export function populatePage() {
  const template = document.querySelector("#engine-template").content;
  for (const engineClass of completionEngines.list) {
    const el = template.cloneNode(true);
    const engine = new engineClass();
    const h4 = el.querySelector("h4");
    h4.textContent = engine.constructor.name;
    // This data attribute is used in tests.
    h4.dataset.engine = engine.constructor.name;
    const explanationEl = el.querySelector(".explanation");
    if (engine.example.explanation) {
      explanationEl.textContent = engine.example.explanation;
    } else {
      explanationEl.remove();
    }

    const exampleEl = el.querySelector(".engine-example");
    console.log("exampleEl:", exampleEl);
    if (engine.example.searchUrl && engine.example.keyword) {
      const desc = engine.example.description || engine.constructor.name;
      exampleEl.querySelector("pre").textContent =
        `${engine.example.keyword}: ${engine.example.searchUrl} ${desc}`;
    } else {
      exampleEl.remove();
    }

    const regexpsEl = el.querySelector(".regexps");
    if (engine.regexps) {
      let content = "";
      for (const re of engine.regexps) {
        content += `${cleanUpRegexp(re)}\n`;
      }
      regexpsEl.querySelector("pre").textContent = content;
    } else {
      regexpsEl.remove();
    }
    document.querySelector("#engine-list").appendChild(el);
  }
}

const testEnv = globalThis.window == null;
if (!testEnv) {
  document.addEventListener("DOMContentLoaded", populatePage);
}
