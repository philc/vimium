var utils = {
  deepcopy: function(original) {
    var result;
    if (typeof original == 'object') {
      if (original === null) {
        result = null;
      } else {
        result = original.constructor === Array ? [] : {};
        for (var i in original)
          if (original.hasOwnProperty(i))
            result[i] = this.deepcopy(original[i]);
      }
    } else {
      result = original;
    }

    return result;
  },
  extendWithSuper: function(original, ext) {
    var result = this.deepcopy(original);
    var tmpSuper = result._super;
    result._superFunctions = {};
    result._super = function(fname) { return this._superFunctions[fname].bind(this); }
    for (var i in ext)
      if (ext.hasOwnProperty(i)) {
        if (typeof ext[i] == 'function' && typeof original[i] == 'function')
          result._superFunctions[i] = this.deepcopy(original[i]);
        result[i] = this.deepcopy(ext[i]);
      }
    return result;
  },
};
