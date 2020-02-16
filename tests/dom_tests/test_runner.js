Tests.outputMethod = function(...args) {
  let newOutput = args.join("\n");
  // Escape html
  newOutput = newOutput.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  // Highlight the source of the error
  newOutput = newOutput.replace(/\/([^:/]+):([0-9]+):([0-9]+)/, "/<span class='errorPosition'>$1:$2</span>:$3");
  document.getElementById("output-div").innerHTML += "<div class='output-section'>" + newOutput + "</div>";
  console.log.apply(console, args);
};

// Puppeteer will call the tests manually
if (!navigator.userAgent.includes("HeadlessChrome")) {
  console.log("we're not in headless chrome");
  // ensure the extension has time to load before commencing the tests
  document.addEventListener("DOMContentLoaded", () => setTimeout(Tests.run, 200));
}
