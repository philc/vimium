import "./all_content_scripts.js";

import * as completionEngines from "../background_scripts/completion_engines.js";

function cleanUpRegexp(re) {
  return re.toString()
    .replace(/^\//, "")
    .replace(/\/$/, "")
    .replace(/\\\//g, "/");
}

function populatePage() {
  const html = [];
  for (const engineClass of completionEngines.list) {
    const engine = new engineClass();
    const name = engine.constructor.name;
    // This data attribute is used in tests.
    html.push(`<h4 data-engine="${name}">${name}</h4>\n`);
    html.push('<div class="engine">');
    if (engine.example.explanation) {
      html.push(`<p>${engine.example.explanation}</p>`);
    }
    if (engine.example.searchUrl && engine.example.keyword) {
      if (!engine.example.description) {
        engine.example.description = engine.constructor.name;
      }
      html.push("<p>");
      html.push("Example:");
      html.push("<pre>");
      html.push(
        `${engine.example.keyword}: ${engine.example.searchUrl} ${engine.example.description}`,
      );
      html.push("</pre>");
      html.push("</p>");
    }

    if (engine.regexps) {
      html.push("<p>");
      html.push(`Regular expression${1 < engine.regexps.length ? "s" : ""}:`);
      html.push("<pre>");
      for (let re of engine.regexps) {
        html.push(`${cleanUpRegexp(re)}\n`);
      }
      html.push("</pre>");
      html.push("</p>");
    }
    html.push("</div>");
  }

  document.getElementById("engineList").innerHTML = html.join("");
}

const testEnv = globalThis.window == null;
if (!testEnv) {
  document.addEventListener("DOMContentLoaded", populatePage);
}

export { populatePage };
