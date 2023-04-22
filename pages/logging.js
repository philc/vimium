const $ = (id) => document.getElementById(id);

document.addEventListener("DOMContentLoaded", function () {
  DomUtils.injectUserCss(); // Manually inject custom user styles.
  $("vimiumVersion").innerText = Utils.getCurrentVersion();

  chrome.storage.local.get(
    "installDate",
    (items) => $("installDate").innerText = items.installDate.toString(),
  );
});
