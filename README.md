Mustache Trimmer - Cleanly shaves your mustache into pure JS
================

Mustache Trimmer is a Ruby library that compiles [Mustache](http://mustache.github.com/) templates into pure Javascript functions.

Installation
------------

    gem install mustache-trimmer

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

Caveats
-------

The compiler is not fully [mustache-spec](https://github.com/mustache/spec) compliant. All of the modules are supported except for the optional lambda section. This module requires a mustache parser to be present at runtime.

Instead of lambdas being passed the raw text of a section, a closure is passed as the first argument. Simply call the function to render the section.

    {{#cacheByUserId}}
      Some expensive stuff.
    {{/cacheByUserId}}

    cacheByUserId: function(section) {
      var key, value;
      key = "user:#{id}";
      if (value = cache[key]) {
        return value;
      } else {
        value = section();
        cache[key] = value;
        return value;
      }
    }

Pro Tip
-------

Use the [Google Closure Compiler](http://closure-compiler.appspot.com/). Its really good at inlining the template helper functions.

    window.hello=function(a){var b,c;b=[];c=[];c.push(a);b.push("Hello ");if((a=function(f){var d,e;for(d=c.length-1;d>=0;d-=1)if(e=c[d][f])return e}("planet"))&&a.constructor&&a.call&&a.apply)a=a();b.push((""+a).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"));return b.join("")};

License
-------

Copyright (c) 2011 Joshua Peek.

Released under the MIT license. See `LICENSE` for details.
