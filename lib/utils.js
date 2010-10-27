String.prototype.trim = function () {
    return this.replace(/^\s*/, "").replace(/\s*$/, "");
}

Log = {
    mode: 'dev',
    log: function () {
        if (Log.mode == 'dev') {
            for (var i = 0; i < arguments.length; i++) {
                console.debug(arguments[i]);
            }
        }
    }
}

// log
var l = Log.log;