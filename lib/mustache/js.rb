require 'mustache'
require 'mustache/javascript_generator'

class Mustache
  def self.to_javascript(source)
    template = templateify(source)
    JavascriptGenerator.new.compile(template.tokens)
  end
end
