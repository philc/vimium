"use strict";
if (window.forTrusted == null) {
    window.forTrusted = handler => (function (event) {
        if (event && event.isTrusted) {
            return handler.apply(this, arguments);
        }
        else {
            return true;
        }
    });
}
let browserInfo = null;
if (window.browser && browser.runtime && browser.runtime.getBrowserInfo) {
    browserInfo = browser.runtime.getBrowserInfo();
}
let Utils = {
    isFirefox: (function () {
        const isFirefox = typeof InstallTrigger !== 'undefined';
        return () => isFirefox;
    })(),
    firefoxVersion: (function () {
        let ffVersion = undefined;
        if (browserInfo) {
            browserInfo.then(info => {
                ffVersion = info != null
                    ? info.version
                    : undefined;
                browserInfo = undefined;
            });
        }
        return () => ffVersion || browserInfo;
    })(),
    isExtensionPage(win) {
        if (win == null) {
            win = window;
        }
        try {
            return ((win.document.location != null ? win.document.location.origin : undefined) + '/')
                === chrome.extension.getURL('');
        }
        catch (error) { }
    },
    isBackgroundPage() {
        return chrome.extension.getBackgroundPage
            && chrome.extension.getBackgroundPage() === window;
    },
    escapeRegexSpecialCharacters: (function () {
        const escapeRegex = /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g;
        return (str) => str.replace(escapeRegex, '\\$&');
    })(),
    escapeHtml(string) {
        return string.replace(/</g, '&lt;').replace(/>/g, '&gt;');
    },
    createUniqueId: (function () {
        let id = 0;
        return () => id += 1;
    })(),
    hasChromePrefix: (function () {
        const chromePrefixes = ['about:', 'view-source:', 'extension:', 'chrome-extension:', 'data:'];
        return (url) => chromePrefixes.some(prefix => url.startsWith(prefix));
    })(),
    hasJavascriptPrefix(url) {
        return url.startsWith('javascript:');
    },
    hasFullUrlPrefix: (function () {
        const urlPrefix = new RegExp('^[a-z][-+.a-z0-9]{2,}://.');
        return (url) => urlPrefix.test(url);
    })(),
    decodeURIByParts(uri) {
        return uri.split(/(?=%)/).map(function (uriComponent) {
            try {
                return decodeURIComponent(uriComponent);
            }
            catch (error) {
                return uriComponent;
            }
        }).join('');
    },
    createFullUrl(partialUrl) {
        if (this.hasFullUrlPrefix(partialUrl)) {
            return partialUrl;
        }
        else {
            return ('http://' + partialUrl);
        }
    },
    isUrl(str) {
        if (str.includes(' ')) {
            return false;
        }
        if (this.hasFullUrlPrefix(str)) {
            return true;
        }
        const urlRegex = new RegExp('^(?:([^:]+)(?::([^:]+))?@)?'
            + '([^:]+|\\[[^\\]]+\\])'
            + '(?::(\\d+))?$');
        const longTlds = ['arpa', 'asia', 'coop', 'info', 'jobs', 'local', 'mobi', 'museum', 'name', 'onion'];
        const specialHostNames = ['localhost'];
        const match = urlRegex.exec((str.split('/'))[0]);
        if (!match)
            return false;
        const hostName = match[3];
        if (specialHostNames.includes(hostName)) {
            return true;
        }
        if (hostName.includes(':')) {
            return true;
        }
        const dottedParts = hostName.split('.');
        if (dottedParts.length > 1) {
            const lastPart = dottedParts.pop();
            if ((2 <= lastPart.length && lastPart.length <= 3) || longTlds.includes(lastPart)) {
                return true;
            }
        }
        if (/^(\d{1,3}\.){3}\d{1,3}$/.test(hostName)) {
            return true;
        }
        return false;
    },
    createSearchQuery(query) {
        query = query.join().split(/\s+/);
        return query.map(encodeURIComponent).join('+');
    },
    createSearchUrl(query, searchUrl) {
        searchUrl = Settings.get('searchUrl');
        if (!['%s', '%S'].some(token => searchUrl.indexOf(token) >= 0))
            searchUrl += '%s';
        searchUrl = searchUrl.replace(/%S/g, query);
        return searchUrl.replace(/%s/g, this.createSearchQuery(query));
    },
    extractQuery: (() => {
        const queryTerminator = new RegExp('[?&#/]');
        const httpProtocolRegexp = new RegExp('^https?://');
        return function (searchUrl, url) {
            let suffixTerms;
            url = url.replace(httpProtocolRegexp);
            searchUrl = searchUrl.replace(httpProtocolRegexp);
            [searchUrl, ...suffixTerms] = searchUrl.split('%s');
            if (!url.startsWith(searchUrl)) {
                return null;
            }
            for (let suffix of suffixTerms) {
                if (!(0 <= url.indexOf(suffix))) {
                    return null;
                }
            }
            try {
                return url.slice(searchUrl.length).split(queryTerminator)[0].split('+').map(decodeURIComponent).join(' ');
            }
            catch (error) {
                return null;
            }
        };
    })(),
    convertToUrl(string) {
        string = string.trim();
        if (Utils.hasChromePrefix(string)) {
            return string;
        }
        else if (Utils.hasJavascriptPrefix(string)) {
            if (Utils.haveChromeVersion('46.0.2467.2')) {
                return string;
            }
            else {
                return Utils.decodeURIByParts(string);
            }
        }
        else if (Utils.isUrl(string)) {
            return Utils.createFullUrl(string);
        }
        else {
            return Utils.createSearchUrl(string);
        }
    },
    isString(obj) {
        return (typeof obj === 'string') || obj instanceof String;
    },
    distinctCharacters(str) {
        const chars = str.split('');
        return Array.from(new Set(chars)).sort().join('');
    },
    haveChromeVersion(required) {
        const match = window.navigator.userAgent.match(/Chrom(e|ium)\/(.*?) /);
        const chromeVersion = match ? match[2] : null;
        return chromeVersion && (0 <= compareVersions(chromeVersion, required));
    },
    zip(arrays) {
        return arrays[0].map((_, i) => arrays.map(array => array[i]));
    },
    hasUpperCase(s) {
        return s.toLowerCase() !== s;
    },
    matchesAnyRegexp(regexps, string) {
        for (let re of regexps) {
            if (re.test(string)) {
                return true;
            }
        }
        return false;
    },
    setTimeout(ms, func) {
        return setTimeout(func, ms);
    },
    nextTick(func) {
        return this.setTimeout(0, func);
    },
    makeIdempotent(func) {
        return function (...args) {
            let previousFunc, ref;
            const result = ([previousFunc, func] = Array.from(ref = [func, null]), ref)[0];
            if (result) {
                return result(...Array.from(args || []));
            }
        };
    },
    monitorChromeStorage(key, setter) {
        return chrome.storage.local.get(key, (obj) => {
            if (obj[key] != null) {
                setter(obj[key]);
            }
            return chrome.storage.onChanged.addListener((changes, area) => {
                if (changes[key] && (changes[key].newValue !== undefined)) {
                    return setter(changes[key].newValue);
                }
            });
        });
    },
};
Function.prototype.curry = function () {
    const fixedArguments = Array.copy(arguments);
    const fn = this;
    return function () {
        return fn.apply(this, fixedArguments.concat(Array.copy(arguments)));
    };
};
Array.copy = array => Array.prototype.slice.call(array, 0);
String.prototype.reverse = function () {
    return this.split('').reverse().join('');
};
class SimpleCache {
    constructor(expiry, entries) {
        if (expiry == null) {
            expiry = 60 * 60 * 1000;
        }
        this.expiry = expiry;
        if (entries == null) {
            entries = 1000;
        }
        this.entries = entries;
        this.cache = {};
        this.previous = {};
        this.lastRotation = new Date();
    }
    has(key) {
        this.rotate();
        return (key in this.cache) || key in this.previous;
    }
    set(key, value = null) {
        this.rotate();
        delete this.previous[key];
        if (value != null) {
            return this.cache[key] = value;
        }
        else {
            delete this.cache[key];
            return null;
        }
    }
    get(key) {
        this.rotate();
        if (key in this.cache) {
            return this.cache[key];
        }
        else if (key in this.previous) {
            this.cache[key] = this.previous[key];
            delete this.previous[key];
            return this.cache[key];
        }
        else {
            return null;
        }
    }
    rotate(force) {
        if (force == null) {
            force = false;
        }
        Utils.nextTick(() => {
            if (force
                || (this.entries < Object.keys(this.cache).length)
                || (this.expiry < (new Date().getTime() - this.lastRotation.getTime()))) {
                this.lastRotation = new Date();
                this.previous = this.cache;
                return this.cache = {};
            }
        });
    }
    clear() {
        this.rotate(true);
        return this.rotate(true);
    }
}
class AsyncDataFetcher {
    constructor(fetch) {
        this.data = null;
        this.queue = [];
        Utils.nextTick(() => {
            return fetch((data) => {
                this.data = data;
                for (let callback of this.queue) {
                    callback(this.data);
                }
                return this.queue = null;
            });
        });
    }
    use(callback) {
        if (this.data != null) {
            return callback(this.data);
        }
        else {
            return this.queue.push(callback);
        }
    }
}
class JobRunner {
    constructor(jobs) {
        this.jobs = jobs;
        this.fetcher = new AsyncDataFetcher(callback => {
            return this.jobs.map((job) => (job => {
                Utils.nextTick(() => {
                    return job(() => {
                        this.jobs = this.jobs.filter((j) => j !== job);
                        if (this.jobs.length === 0) {
                            return callback(true);
                        }
                    });
                });
                return null;
            })(job));
        });
    }
    onReady(callback) {
        return this.fetcher.use(callback);
    }
}
Object.assign(window, { Utils, SimpleCache, AsyncDataFetcher, JobRunner });
