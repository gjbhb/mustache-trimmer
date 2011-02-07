require 'mustache'

class Mustache
  class JavascriptGenerator
    def initialize
      @n = 0
      @locals = []
      @helpers = {}
      @indentation = ""
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

    def locals(indent)
      "#{indent}var #{@locals.join(', ')};\n"
    end

    def partials(indent)
      @partials.values.join("\n  ")
    end

    def compile(exp, indent = '')
      local :out

      body = compile!(exp, indent+'  ')

      helpers = self.helpers(indent+'  ')
      partials = self.partials(indent+'  ')
      locals = self.locals(indent+'  ')

      js = ""
      js << indent << "function (obj) {\n"
      js << locals
      js << indent << "  out = [];\n"
      js << helpers
      js << partials
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
        args = exp[2..-1]
        args.push(indent)
        send("on_#{exp[1]}", *args)
      else
        raise "Unhandled exp: #{exp.first}"
      end
    end

    def on_section(name, content, raw, indent)
      @helpers[:fetch] = @helpers[:isEmpty] = true
      @helpers[:isObject] = @helpers[:isArray] = @helpers[:isFunction] = true

      f, v, i = local, local, local
      code = compile!(content)

      <<-JS.gsub(/^        /, indent)
        #{f} = function #{f}(out) {
#{code.gsub(/^/, '          ')}
        };
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
      code = compile!(content)

      <<-JS.gsub(/^        /, indent)
        #{f} = function #{f}(out) {
#{code.gsub(/^/, '          ')}
        };
        #{v} = fetch(#{name.inspect});
        if (isEmpty(#{v})) {
          #{f}(out);
        }
      JS
    end

    def on_partial(name, indentation, indent)
      unless js = @partial_calls[name]
        js = @partial_calls[name] = "#{name}();\n"

        old_indentation, @indentation = @indentation, indentation

        source   = Mustache.partial(name)
        template = Mustache.templateify(source)
        body     = compile!(template.tokens)

        @indentation = old_indentation

        @partials[name] = <<-JS.gsub(/^          /, indent)
          function #{name}(obj) {
#{body.gsub(/^/, '            ')}
          }
        JS
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

    def str(s, indent)
      s = s.gsub(/^/, @indentation) if !@indentation.empty?
      "#{indent}out.push(#{s.inspect});\n"
    end

    def local(name = nil)
      if name
        @locals << name.to_sym
      else
        @n += 1
        name = :"l#{@n}"
        @locals << name
        name
      end
    end
  end
end
