const $ = id => document.getElementById(id);

document.addEventListener("DOMContentLoaded", function() {
  DomUtils.injectUserCss(); // Manually inject custom user styles.
  $("vimiumVersion").innerText = Utils.getCurrentVersion();

  chrome.storage.local.get("installDate", items => $("installDate").innerText = items.installDate.toString());

  const branchRefRequest = new XMLHttpRequest();
  branchRefRequest.addEventListener("load", function() {
    const branchRefParts = branchRefRequest.responseText.split("refs/heads/", 2);
    if (branchRefParts.length === 2)
      $("branchRef").innerText = branchRefParts[1];
    else
      $("branchRef").innerText = `HEAD detatched at ${branchRefParts[0]}`;
    $("branchRef-wrapper").classList.add("no-hide");
  });
  branchRefRequest.open("GET", chrome.extension.getURL(".git/HEAD"));
  branchRefRequest.send();
});
