var utils = {
  // probably doesn't handle some cases correctly, but it works fine for what
  // we have now
  deepCopy: function(original) {
    var result;
    if (typeof original == 'object') {
      if (original === null) {
        result = null;
      } else {
        result = original.constructor === Array ? [] : {};
        for (var i in original)
          if (original.hasOwnProperty(i))
            result[i] = this.deepCopy(original[i]);
      }
    } else {
      result = original;
    }

    return result;
  },

  /*
   * Extends 'original' with 'ext'. If a function in 'ext' also exists in
   * 'original', let the 'original' function be accessible in the new object
   * via a  ._super(functionName as String) method. _Cannot_ be used on its
   * result to achieve 'two-level' inheritance.
   */
  extendWithSuper: function(original, ext) {
    var result = this.deepCopy(original);
    var tmpSuper = result._super;
    result._superFunctions = {};
    result._super = function(fname) { return this._superFunctions[fname].bind(this); }
    for (var i in ext)
      if (ext.hasOwnProperty(i)) {
        if (typeof ext[i] == 'function' && typeof original[i] == 'function')
          result._superFunctions[i] = this.deepCopy(original[i]);
        result[i] = this.deepCopy(ext[i]);
      }
    return result;
  },
};
