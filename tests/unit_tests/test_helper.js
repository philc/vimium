require("../shoulda.js/shoulda.js");
global.extend = function(hash1, hash2) {
  for (let key of Object.keys(hash2)) {
    hash1[key] = hash2[key];
  }
  return hash1;
};
