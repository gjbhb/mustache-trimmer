require 'test/unit'

require 'mustache/js'

class TestGenerator < Test::Unit::TestCase
  def generator
    @generator ||= Mustache::JavascriptGenerator.new
  end

  def test_str
    assert_equal <<-JS, generator.str("Hello", "      ")
      out.push("Hello");
    JS
  end

  def test_closure
    assert_equal <<-JS, generator.closure("greeting", [:static, "Hello"], "      ")
      function greeting(out) {
        out.push("Hello");
      };
    JS

    assert_equal <<-JS, generator.closure("greeting", [:mustache, :utag, [:mustache, :fetch, ["Hello"]]], "      ")
      function greeting(out) {
        var l1;
        l1 = fetch("Hello");
        if (isFunction(l1)) {
          l1 = l1.call(stack[stack.length - 1]);
        }
        if (!isEmpty(l1)) {
          out.push(l1);
        }
      };
    JS
  end

  def test_on_utag
    assert_equal <<-JS, generator.on_utag([:mustache, :fetch, ["name"]], "      ")
      l1 = fetch("name");
      if (isFunction(l1)) {
        l1 = l1.call(stack[stack.length - 1]);
      }
      if (!isEmpty(l1)) {
        out.push(l1);
      }
    JS
  end

  def test_on_etag
    assert_equal <<-JS, generator.on_etag([:mustache, :fetch, ["name"]], "      ")
      l1 = fetch("name");
      if (isFunction(l1)) {
        l1 = l1.call(stack[stack.length - 1]);
      }
      if (!isEmpty(l1)) {
        out.push(escape(l1));
      }
    JS
  end

  def test_on_inverted_section
    assert_equal <<-JS, generator.on_inverted_section([:mustache, :fetch, ["name"]], [:static, "Hello"], nil, "      ")
      l1 = function l1(out) {
        out.push("Hello");
      };
      l2 = fetch("name");
      if (isEmpty(l2)) {
        l1(out);
      }
    JS
  end

  def test_on_section
    assert_equal <<-JS, generator.on_section([:mustache, :fetch, ["name"]], [:static, "Hello"], nil, "      ")
      l1 = function l1(out) {
        out.push("Hello");
      };
      l2 = fetch("name");
      if (!isEmpty(l2)) {
        if (isFunction(l2)) {
          out.push(l2.call(stack[stack.length - 1], function () {
            var out = [];
            l1(out);
            return out.join("");
          }));
        } else if (isArray(l2)) {
          for (l3 = 0; l3 < l2.length; l3 += 1) {
            stack.push(l2[l3]);
            l1(out);
            stack.pop();
          }
        } else if (isObject(l2)) {
          stack.push(l2);
          l1(out);
          stack.pop();
        } else {
          l1(out);
        }
      }
    JS
  end
end
