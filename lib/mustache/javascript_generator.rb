require 'mustache'

class Mustache
  class JavascriptGenerator
    def initialize
      @n = 0
      @locals = [[]]
      @helpers = {}
      @partials = {}
      @partial_calls = {}
    end

    def helpers
      out = ""

      if @helpers[:fetch]
        local :stack
        local :fetch
        out << <<-JS
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
        JS
      end

      if @helpers[:escape]
        local :escape
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
        local :isEmpty
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
        local :isArray
        out << <<-JS
          isArray = Array.isArray || function isArray(obj) {
            return Object.prototype.toString.call(obj) === '[object Array]';
          };
        JS
      end

      if @helpers[:isObject]
        local :isObject
        out << <<-JS
          isObject = function isObject(obj) {
            return (obj && typeof obj === 'object');
          };
        JS
      end

      if @helpers[:isFunction]
        local :isFunction
        out << <<-JS
          isFunction = function isFunction(obj) {
            return !!(obj && obj.constructor && obj.call && obj.apply);
          };
        JS
      end

      if @helpers[:reduce]
        local :reduce
        out << <<-JS
          reduce = Array.prototype.reduce || function reduce(iterator, memo) {
            var i;
            for (i = 0; i < this.length; i++) {
              memo = iterator(memo, this[i]);
            }
            return memo;
          };
        JS

        local :traverse
        out << <<-JS
          traverse = function traverse(value, key) {
            return value && value[key];
          };
        JS
      end

      out
    end

    def locals
      if @locals.last.any?
        "var #{@locals.last.join(', ')};\n"
      end
    end

    def partials
      @partials.values.join("\n")
    end

    def compile(exp)
      local :out

      body = compile!(exp)

      helpers = self.helpers
      partials = self.partials
      locals = self.locals

      <<-JS
        function (obj) {
          #{locals}
          out = [];
          #{helpers}
          #{partials}
          #{body}
          return out.join("");
        }
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
      @helpers[:fetch] = @helpers[:isEmpty] = true
      @helpers[:isObject] = @helpers[:isArray] = @helpers[:isFunction] = true

      f, v, i = local, local, local

      <<-JS
        #{f} = #{closure(f, content)}
        #{v} = #{compile!(name)};
        if (!isEmpty(#{v})) {
          if (isFunction(#{v})) {
            out.push(#{v}.call(stack[stack.length - 1], function () {
              var out = [];
              #{f}(out);
              return out.join("");
            }));
          } else if (isArray(#{v})) {
            for (#{i} = 0; #{i} < #{v}.length; #{i} += 1) {
              stack.push(#{v}[#{i}]);
              #{f}(out);
              stack.pop();
            }
          } else if (isObject(#{v})) {
            stack.push(#{v});
            #{f}(out);
            stack.pop();
          } else {
            #{f}(out);
          }
        }
      JS
    end

    def on_inverted_section(name, content, raw)
      @helpers[:isEmpty] = true
      @helpers[:fetch] = true

      f, v = local, local

      <<-JS
        #{f} = #{closure(f, content)}
        #{v} = #{compile!(name)};
        if (isEmpty(#{v})) {
          #{f}(out);
        }
      JS
    end

    def on_partial(name, indentation)
      unless js = @partial_calls[name]
        js = @partial_calls[name] = "#{name}(out);\n"

        source   = Mustache.partial(name).to_s.gsub(/^/, indentation)
        template = Mustache.templateify(source)

        @partials[name] = closure(name, template.tokens).chomp
      end

      js
    end

    def on_utag(name)
      @helpers[:fetch] = true
      @helpers[:isFunction] = true
      @helpers[:isEmpty] = true

      v = local

      <<-JS
        #{v} = #{compile!(name)};
        if (isFunction(#{v})) {
          #{v} = #{v}.call(stack[stack.length - 1]);
        }
        if (!isEmpty(#{v})) {
          out.push(#{v});
        }
      JS
    end

    def on_etag(name)
      @helpers[:fetch] = true
      @helpers[:isFunction] = true
      @helpers[:isEmpty] = @helpers[:escape] = true

      v = local

      <<-JS
        #{v} = #{compile!(name)};
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
        "fetch(#{names.first.inspect})"
      else
        @helpers[:reduce] = true
        initial, *rest = names
        "reduce.call(#{rest.inspect}, traverse, fetch(#{initial.inspect}))"
      end
    end

    def closure(name, tokens)
      @locals.push([])
      code = compile!(tokens)
      locals = self.locals
      @locals.pop

      <<-JS
        function #{name}(out) {
          #{locals}
          #{code}
        };
      JS
    end

    def str(s)
      "out.push(#{s.inspect});\n"
    end

    def local(name = nil)
      if name
        @locals.last << name.to_sym
      else
        @n += 1
        name = :"l#{@n}"
        @locals.last << name
        name
      end
    end
  end
end
