var utils = {
  /*
   * Takes a dot-notation object string and call the function
   * that it points to with the correct value for 'this'.
   */
  invokeCommandString: function(str, argArray) {
    var components = str.split('.');
    var obj = window;
    for (var i = 0; i < components.length - 1; i++)
      obj = obj[components[i]];
    var func = obj[components.pop()];
    return func.apply(obj, argArray);
  },
};
