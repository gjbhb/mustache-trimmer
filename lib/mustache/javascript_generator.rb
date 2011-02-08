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

    def helpers(indent)
      out = ""

      if @helpers[:fetch]
        local :stack
        local :fetch
        out << <<-JS.gsub(/^          /, indent)
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
        out << <<-JS.gsub(/^          /, indent)
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
        out << <<-JS.gsub(/^          /, indent)
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
        out << <<-JS.gsub(/^          /, indent)
          isArray = Array.isArray || function isArray(obj) {
            return Object.prototype.toString.call(obj) === '[object Array]';
          };
        JS
      end

      if @helpers[:isObject]
        local :isObject
        out << <<-JS.gsub(/^          /, indent)
          isObject = function isObject(obj) {
            return (obj && typeof obj === 'object');
          };
        JS
      end

      if @helpers[:isFunction]
        local :isFunction
        out << <<-JS.gsub(/^          /, indent)
          isFunction = function isFunction(obj) {
            return !!(obj && obj.constructor && obj.call && obj.apply);
          };
        JS
      end

      out
    end

    def locals
      if @locals.last.any?
        "var #{@locals.last.join(', ')};\n"
      else
        ""
      end
    end

    def partials(indent)
      indent + @partials.values.join("\n#{indent}")
    end

    def compile(exp, indent = '')
      local :out

      body = compile!(exp, indent+'  ')

      helpers = self.helpers(indent+'  ')
      partials = self.partials(indent+'  ')
      locals = indent + '  ' + self.locals

      js = ""
      js << indent << "function (obj) {\n"
      js << locals
      js << indent << "  out = [];\n"
      js << helpers
      js << partials << "\n"
      js << body
      js << indent << "  return out.join(\"\");\n"
      js << indent << "}"
      js
    end

    def compile!(exp, indent = '')
      case exp.first
      when :multi
        exp[1..-1].map { |e| compile!(e, indent) }.join
      when :static
        str(exp[1], indent)
      when :mustache
        send("on_#{exp[1]}", *(exp[2..-1] + [indent]))
      else
        raise "Unhandled exp: #{exp.first}"
      end
    end

    def on_section(name, content, raw, indent)
      @helpers[:fetch] = @helpers[:isEmpty] = true
      @helpers[:isObject] = @helpers[:isArray] = @helpers[:isFunction] = true

      f, v, i = local, local, local

      <<-JS.gsub(/^        /, indent)
        #{f} = #{closure(f, content, indent).chomp}
        #{v} = fetch(#{name.inspect});
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

    def on_inverted_section(name, content, raw, indent)
      @helpers[:isEmpty] = true
      @helpers[:fetch] = true

      f, v = local, local

      <<-JS.gsub(/^        /, indent)
        #{f} = #{closure(f, content, indent).chomp}
        #{v} = fetch(#{name.inspect});
        if (isEmpty(#{v})) {
          #{f}(out);
        }
      JS
    end

    def on_partial(name, indentation, indent)
      unless js = @partial_calls[name]
        js = @partial_calls[name] = "#{name}(out);\n"

        source   = Mustache.partial(name).to_s.gsub(/^/, indentation)
        template = Mustache.templateify(source)

        @partials[name] = closure(name, template.tokens, indent).chomp
      end

      "#{indent}#{js}"
    end

    def on_utag(name, indent)
      @helpers[:fetch] = true
      @helpers[:isFunction] = true

      v = local

      <<-JS.gsub(/^        /, indent)
        #{v} = fetch(#{name.inspect});
        if (isFunction(#{v})) {
          #{v} = #{v}.call(stack[stack.length - 1]);
        }
        out.push(#{v});
      JS
    end

    def on_etag(name, indent)
      @helpers[:fetch] = @helpers[:escape] = true
      @helpers[:isFunction] = true

      v = local

      <<-JS.gsub(/^        /, indent)
        #{v} = fetch(#{name.inspect});
        if (isFunction(#{v})) {
          #{v} = #{v}.call(stack[stack.length - 1]);
        }
        out.push(escape(#{v}));
      JS
    end

    def closure(name, tokens, indent)
      @locals.push([])
      code = compile!(tokens)
      locals = self.locals
      @locals.pop

      <<-JS.gsub(/^        /, indent)
function #{name}(out) {
          #{locals.chomp}
#{code.gsub(/^/, '          ').chomp}
        };
      JS
    end

    def str(s, indent)
      "#{indent}out.push(#{s.inspect});\n"
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
