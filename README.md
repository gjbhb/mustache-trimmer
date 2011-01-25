Mustache Trimmer (aka Mustache JS compiler)
===========================================

Cleanly shaves your mustache into pure JS

Usage
-----

    require 'mustache/js'
    Mustache.to_javascript("Hello {{planet}}")

Compiled JS function:

    function (obj) {
      var out, l1, stack, fetch, escape, isFunction;
      out = [];
      stack = [];
      stack.push(obj);
      fetch = function fetch(key) {
        var i, v;
        for (i = stack.length - 1; i >= 0; i -= 1) {
          v = stack[i][key];
          if (v) {
            return v;
          }
        }
      };
      escape = function escape(value) {
        return ('' + value)
          .replace(/&/g, '&amp;')
          .replace(/</g, '&lt;')
          .replace(/>/g, '&gt;')
          .replace(/"/g, '&quot;');
      };
      isFunction = function isFunction(obj) {
        return !!(obj && obj.constructor && obj.call && obj.apply);
      };
      out.push("Hello ");
      l1 = fetch("planet");
      if (isFunction(l1)) {
        l1 = l1();
      }
      out.push(escape(l1));
      return out.join("");
    }

