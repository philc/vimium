const $ = (id) => document.getElementById(id);

document.addEventListener("DOMContentLoaded", function () {
  DomUtils.injectUserCss(); // Manually inject custom user styles.
  $("vimiumVersion").innerText = Utils.getCurrentVersion();
});
