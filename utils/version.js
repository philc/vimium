"use strict";
function compareVersions(versionA, versionB) {
    const a = versionA.split('.');
    const b = versionB.split('.');
    const len = Math.max(a.length, b.length);
    for (let i = 0; i < len; i++) {
        const ai = parseInt(a[i] || '0');
        const bi = parseInt(b[i] || '0');
        if (ai < bi) {
            return -1;
        }
        else if (ai > bi) {
            return 1;
        }
    }
    return 0;
}
function getCurrentVersion() {
    return chrome.runtime.getManifest().version;
}
