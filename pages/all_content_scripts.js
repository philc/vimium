// This is the set of all content scripts required to make Vimium's functionality work. This file is
// imported by background pages that we want to work with Vimium's key mappings, e.g. the options
// page. This should be the same list of files as in manifest.js's content_scripts section.

import "../lib/utils.js";
import "../lib/url_utils.js";
import "../lib/keyboard_utils.js";
import "../lib/dom_utils.js";
import "../lib/rect.js";
import "../lib/handler_stack.js";
import "../lib/settings.js";
import "../lib/find_mode_history.js";

import "../content_scripts/mode.js";
import "../content_scripts/ui_component.js";
import "../content_scripts/link_hints.js";
import "../content_scripts/vomnibar.js";
import "../content_scripts/scroller.js";
import "../content_scripts/marks.js";
import "../content_scripts/mode_insert.js";
import "../content_scripts/mode_find.js";
import "../content_scripts/mode_key_handler.js";
import "../content_scripts/mode_visual.js";
import "../content_scripts/hud.js";
import "../content_scripts/mode_normal.js";
import "../content_scripts/vimium_frontend.js";
