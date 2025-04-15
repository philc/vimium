import "../pages/all_content_scripts.js";
import "../pages/vomnibar_page.js";

function setup() {
  Vomnibar.activate(0, {});
}

document.addEventListener("DOMContentLoaded", setup, false);
