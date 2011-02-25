require 'test/unit'

require 'mustache/js'

require 'yaml'
require 'v8'

class TestSpec < Test::Unit::TestCase
  Mustache.template_path = File.expand_path("../partials", __FILE__)

  def setup
    Dir.mkdir(Mustache.template_path)
  end

  def teardown
    partials = Mustache.template_path
    Dir[File.join(partials, '*')].each { |file| File.delete(file) }
    Dir.rmdir(partials)
  end

  def default_test
    assert true
  end

  def self.define_test_method(context, test)
    define_method "test - #{test['name']}" do
      setup_partials(test)
      assert_mustache_spec(context, test)
    end
  end

  def setup_partials(test)
    (test['partials'] || {}).each do |name, content|
      path = File.join(Mustache.template_path, "#{name}.mustache")
      File.open(path, 'w') { |f| f.print(content) }
    end
  end

  def assert_mustache_spec(context, test)
    message = "#{test['desc']}\n"
    message << "Data: #{test['data'].inspect}\n"
    message << "Template: #{test['template'].inspect}\n"
    message << "Partials: #{(test['partials'] || {}).inspect}\n"

    source = actual = nil

    assert_nothing_raised message do
      source = Mustache.to_javascript(test['template'])
    end
    message << "Javascript: #{source}\n"

    assert_nothing_raised message do
      context.eval("var template = #{source};")
      actual = context['template'].call(test['data'])
    end

    assert_equal test['expected'], actual, message
  end
end

context = ::V8::Context.new
YAML::add_builtin_type('code') do |_, val|
  source = val['js']
  context.eval("var lambda = #{source};")
  context['lambda']
end

path = File.expand_path("../**/*.yml", __FILE__)
Dir[path].each do |file|
  spec = YAML.load_file(file)
  name = File.basename(file, '.yml').gsub(/-|~/, "").capitalize

  next if name == 'Lambdas'

  klass_name = "Test#{name}"
  instance_eval "class ::#{klass_name} < TestSpec; end"
  test_suite = Kernel.const_get(klass_name)

  spec['tests'].each do |test|
    test_suite.define_test_method(context, test)
  end
end
