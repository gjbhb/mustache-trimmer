require 'mustache'

class Mustache
  class JavascriptGenerator
    def initialize
      @n        = 0
      @globals  = []
      @locals   = []
      @helpers  = {}
      @partials = {}
    end

    def helpers
      out = ""

      if @helpers[:fetch]
        global :fetch
        out << <<-JS
          fetch = function fetch(stack, key) {
            var i, v;
            for (i = stack.length - 1; i >= 0; i -= 1) {
              v = stack[i][key];
              if (v) {
                return v;
              }
            }
          };
        JS
      end

      if @helpers[:escape]
        global :escape
        out << <<-JS
          escape = function escape(value) {
            return ('' + value)
              .replace(/&/g, '&amp;')
              .replace(/</g, '&lt;')
              .replace(/>/g, '&gt;')
              .replace(/\x22/g, '&quot;');
          };
        JS
      end

      if @helpers[:isEmpty]
        @helpers[:isArray] = @helpers[:isObject] = true
        global :isEmpty
        out << <<-JS
          isEmpty = function isEmpty(obj) {
            var key;

            if (!obj) {
              return true;
            } else if (isArray(obj)) {
              return obj.length === 0;
            } else if (isObject(obj)) {
              for (key in obj) {
                if (obj.hasOwnProperty(key)) {
                  return false;
                }
              }
              return true;
            } else {
              return false;
            }
          };
        JS
      end

      if @helpers[:isArray]
        global :isArray
        out << <<-JS
          isArray = Array.isArray || function (obj) {
            return Object.prototype.toString.call(obj) === '[object Array]';
          };
        JS
      end

      if @helpers[:isObject]
        global :isObject
        out << <<-JS
          isObject = function isObject(obj) {
            return (obj && typeof obj === 'object');
          };
        JS
      end

      if @helpers[:isFunction]
        global :isFunction
        out << <<-JS
          isFunction = function isFunction(obj) {
            return !!(obj && obj.constructor && obj.call && obj.apply);
          };
        JS
      end

      if @helpers[:reduce]
        global :reduce
        out << <<-JS
          reduce = Array.prototype.reduce || function (iterator, memo) {
            var i;
            for (i = 0; i < this.length; i++) {
              memo = iterator(memo, this[i]);
            }
            return memo;
          };
        JS

        global :traverse
        out << <<-JS
          traverse = function traverse(value, key) {
            return value && value[key];
          };
        JS
      end

      out
    end

    def globals
      if @globals.any?
        "var #{@globals.join(', ')};\n"
      else
        ""
      end
    end

    def locals
      if @locals.last.any?
        "var #{@locals.last.join(', ')};\n"
      else
        ""
      end
    end

    def partials
      @partials.values.join("\n")
    end

    def compile(exp)
      main = global
      body = global

      compile_closure!(body, exp)

      helpers = self.helpers

      <<-JS.strip
        (function() {
          #{globals.strip}
          #{helpers.strip}
          #{partials.strip}

          #{main} = function #{main}(obj) {
            var stack, out;
            stack = [];
            stack.push(obj);
            out = [];
            #{body}(stack, out);
            return out.join("");
          };

          return #{main};
        })()
      JS
    end

    def compile!(exp)
      case exp.first
      when :multi
        exp[1..-1].map { |e| compile!(e) }.join
      when :static
        str(exp[1])
      when :mustache
        send("on_#{exp[1]}", *exp[2..-1])
      else
        raise "Unhandled exp: #{exp.first}"
      end
    end

    def on_section(name, content, raw)
      @helpers[:isEmpty] = true
      @helpers[:isObject] = @helpers[:isArray] = @helpers[:isFunction] = true

      f, v, i = global, local(:v), local(:i)

      compile_closure!(f, content)

      <<-JS
        #{v} = #{compile!(name).strip};
        if (!isEmpty(#{v})) {
          if (isFunction(#{v})) {
            out.push(#{v}.call(stack[stack.length - 1], function () {
              var out = [];
              #{f}(stack, out);
              return out.join("");
            }));
          } else if (isArray(#{v})) {
            for (#{i} = 0; #{i} < #{v}.length; #{i} += 1) {
              stack.push(#{v}[#{i}]);
              #{f}(stack, out);
              stack.pop();
            }
          } else if (isObject(#{v})) {
            stack.push(#{v});
            #{f}(stack, out);
            stack.pop();
          } else {
            #{f}(stack, out);
          }
        }
      JS
    end

    def on_inverted_section(name, content, raw)
      @helpers[:isEmpty] = true

      f, v = global, local(:v)

      compile_closure!(f, content)

      <<-JS
        #{v} = #{compile!(name).strip};
        if (isEmpty(#{v})) {
          #{f}(stack, out);
        }
      JS
    end

    def on_partial(name, indentation)
      unless @partials[name]
        @partials[name] = true # Stub for recursion

        source   = Mustache.partial(name).to_s.gsub(/^/, indentation)
        template = Mustache.templateify(source)

        compile_closure!(name, template.tokens)
      end

      "#{name}(stack, out);\n"
    end

    def compile_closure!(name, tokens)
      @locals.push([])
      code = compile!(tokens)
      locals = self.locals
      @locals.pop

      @partials[name] = <<-JS
        #{name} = function #{name}(stack, out) {
          #{locals}
          #{code}
        };
      JS

      nil
    end

    def on_utag(name)
      @helpers[:isFunction] = true
      @helpers[:isEmpty] = true

      v = local(:v)

      <<-JS
        #{v} = #{compile!(name).strip};
        if (isFunction(#{v})) {
          #{v} = #{v}.call(stack[stack.length - 1]);
        }
        if (!isEmpty(#{v})) {
          out.push(#{v});
        }
      JS
    end

    def on_etag(name)
      @helpers[:isFunction] = true
      @helpers[:isEmpty] = @helpers[:escape] = true

      v = local(:v)

      <<-JS
        #{v} = #{compile!(name).strip};
        if (isFunction(#{v})) {
          #{v} = #{v}.call(stack[stack.length - 1]);
        }
        if (!isEmpty(#{v})) {
          out.push(escape(#{v}));
        }
      JS
    end

    def on_fetch(names)
      @helpers[:fetch] = true

      names = names.map { |n| n.to_s }

      case names.length
      when 0
        "stack[stack.length-1]"
      when 1
        "fetch(stack, #{names.first.inspect})"
      else
        @helpers[:reduce] = true
        initial, *rest = names
        "reduce.call(#{rest.inspect}, traverse, fetch(stack, #{initial.inspect}))"
      end
    end

    def str(s)
      "out.push(#{s.inspect});\n"
    end

    def global(name = nil)
      if name
        @globals << name.to_sym
        name
      else
        @n += 1
        name = :"g#{@n}"
        @globals << name
        name
      end
    end

    def local(name = nil)
      raise "not in closure" unless @locals.last
      @locals.last << name.to_sym
      name
    end
  end
end
